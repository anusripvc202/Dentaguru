class ReferralItem {
  final String id;
  final String referrerId;
  final String referrerName;
  final String referrerPhone;
  final String referrerEmail;
  final String referredUserId;
  final String referredUserName;
  final String referredUserPhone;
  final String referredUserEmail;
  final String referralCode;
  final String status;
  final String registrationStatus;
  final String consultationStatus;
  final String? assignedDoctorName;
  final String? assignedClinicName;
  final DateTime createdAt;

  ReferralItem({
    required this.id,
    required this.referrerId,
    this.referrerName = '',
    this.referrerPhone = '',
    this.referrerEmail = '',
    required this.referredUserId,
    this.referredUserName = 'Registered Friend',
    this.referredUserPhone = '',
    this.referredUserEmail = '',
    required this.referralCode,
    this.status = 'REGISTERED',
    this.registrationStatus = 'Verified Account',
    this.consultationStatus = 'Pending Booking',
    this.assignedDoctorName,
    this.assignedClinicName,
    required this.createdAt,
  });

  factory ReferralItem.fromJson(Map<String, dynamic> json) {
    return ReferralItem(
      id: json['id']?.toString() ?? '',
      referrerId: json['referrerId']?.toString() ?? json['referrer_id']?.toString() ?? '',
      referrerName: json['referrerName']?.toString() ?? '',
      referrerPhone: json['referrerPhone']?.toString() ?? '',
      referrerEmail: json['referrerEmail']?.toString() ?? '',
      referredUserId: json['referredUserId']?.toString() ?? json['referred_user_id']?.toString() ?? '',
      referredUserName: json['referredUserName']?.toString() ?? 'Registered Friend',
      referredUserPhone: json['referredUserPhone']?.toString() ?? '',
      referredUserEmail: json['referredUserEmail']?.toString() ?? '',
      referralCode: json['referralCode']?.toString() ?? json['referral_code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'REGISTERED',
      registrationStatus: json['registrationStatus']?.toString() ?? 'Verified Account',
      consultationStatus: json['consultationStatus']?.toString() ?? 'Pending Booking',
      assignedDoctorName: json['assignedDoctorName']?.toString(),
      assignedClinicName: json['assignedClinicName']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ReferralStats {
  final int totalReferred;
  final int registered;
  final int consultationBooked;
  final int consultationsCompleted;

  ReferralStats({
    this.totalReferred = 0,
    this.registered = 0,
    this.consultationBooked = 0,
    this.consultationsCompleted = 0,
  });

  factory ReferralStats.fromJson(Map<String, dynamic> json) {
    return ReferralStats(
      totalReferred: int.tryParse(json['totalReferred']?.toString() ?? '0') ?? 0,
      registered: int.tryParse(json['registered']?.toString() ?? '0') ?? 0,
      consultationBooked: int.tryParse(json['consultationBooked']?.toString() ?? '0') ?? 0,
      consultationsCompleted: int.tryParse(json['consultationsCompleted']?.toString() ?? '0') ?? 0,
    );
  }
}

class TopReferrer {
  final String referrerId;
  final String name;
  final String email;
  final String phone;
  final String referralCode;
  final int totalReferrals;
  final int completedConsultations;

  TopReferrer({
    required this.referrerId,
    required this.name,
    this.email = '',
    this.phone = '',
    required this.referralCode,
    this.totalReferrals = 0,
    this.completedConsultations = 0,
  });

  factory TopReferrer.fromJson(Map<String, dynamic> json) {
    return TopReferrer(
      referrerId: json['referrerId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Active Patient',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      referralCode: json['referralCode']?.toString() ?? '',
      totalReferrals: int.tryParse(json['totalReferrals']?.toString() ?? '0') ?? 0,
      completedConsultations: int.tryParse(json['completedConsultations']?.toString() ?? '0') ?? 0,
    );
  }
}

class AdminReferralAnalytics {
  final int totalReferrals;
  final int totalRegistered;
  final int totalConsultations;
  final String conversionRateRegistration;
  final String conversionRateConsultation;
  final List<TopReferrer> topReferringPatients;

  AdminReferralAnalytics({
    this.totalReferrals = 0,
    this.totalRegistered = 0,
    this.totalConsultations = 0,
    this.conversionRateRegistration = '100.0%',
    this.conversionRateConsultation = '0.0%',
    this.topReferringPatients = const [],
  });

  factory AdminReferralAnalytics.fromJson(Map<String, dynamic> json) {
    final list = json['topReferringPatients'] as List<dynamic>? ?? [];
    return AdminReferralAnalytics(
      totalReferrals: int.tryParse(json['totalReferrals']?.toString() ?? '0') ?? 0,
      totalRegistered: int.tryParse(json['totalRegistered']?.toString() ?? '0') ?? 0,
      totalConsultations: int.tryParse(json['totalConsultations']?.toString() ?? '0') ?? 0,
      conversionRateRegistration: json['conversionRateRegistration']?.toString() ?? '100.0%',
      conversionRateConsultation: json['conversionRateConsultation']?.toString() ?? '0.0%',
      topReferringPatients: list.map((item) => TopReferrer.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}
