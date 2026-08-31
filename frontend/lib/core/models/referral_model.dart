class PatientReferral {
  final String id;
  final String referrerPatientId;
  final String referrerPatientName;
  final String referrerPatientPhone;
  final String referrerPatientEmail;

  final String? referredPatientId;
  final String referredPatientName;
  final String referredPatientMobile;
  final String referredPatientAge;
  final String referredPatientGender;
  final String referredPatientCity;
  final String referredPatientPincode;
  final String referredPatientLocation;

  final String requiredSpecialist;
  final String clinicalComplaint;

  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final String doctorClinicName;
  final String doctorCity;
  final String doctorPincode;
  final String doctorLocation;
  final List<String> doctorLanguages;

  final String status; // 'Pending' | 'Accepted' | 'Rejected'
  final String? rejectionReason;
  final String whatsappStatus; // 'Pending' | 'Sent' | 'Failed'
  final DateTime referralDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  PatientReferral({
    required this.id,
    required this.referrerPatientId,
    this.referrerPatientName = 'Patient',
    this.referrerPatientPhone = '',
    this.referrerPatientEmail = '',
    this.referredPatientId,
    required this.referredPatientName,
    required this.referredPatientMobile,
    this.referredPatientAge = '',
    this.referredPatientGender = '',
    this.referredPatientCity = '',
    this.referredPatientPincode = '',
    this.referredPatientLocation = '',
    required this.requiredSpecialist,
    required this.clinicalComplaint,
    required this.doctorId,
    this.doctorName = 'Specialist',
    this.doctorSpecialty = '',
    this.doctorClinicName = '',
    this.doctorCity = '',
    this.doctorPincode = '',
    this.doctorLocation = '',
    this.doctorLanguages = const ['English'],
    this.status = 'Pending',
    this.rejectionReason,
    this.whatsappStatus = 'Pending',
    DateTime? referralDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : referralDate = referralDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PatientReferral.fromJson(Map<String, dynamic> json) {
    List<String> langs = ['English'];
    if (json['doctorLanguages'] is List) {
      langs = (json['doctorLanguages'] as List).map((e) => e.toString()).toList();
    } else if (json['doctor'] is Map && json['doctor']['languages'] is List) {
      langs = (json['doctor']['languages'] as List).map((e) => e.toString()).toList();
    }

    String docName = json['doctorName']?.toString() ??
        (json['doctor'] is Map ? (json['doctor']['users']?['name'] ?? json['doctor']['name'])?.toString() : null) ??
        'Specialist';
    if (!docName.startsWith('Dr.') && !docName.startsWith('Dr ')) {
      docName = 'Dr. $docName';
    }

    final referrerName = json['referrerPatientName']?.toString() ??
        (json['referrer'] is Map ? json['referrer']['name']?.toString() : null) ??
        json['referrerName']?.toString() ??
        'Patient Referrer';

    return PatientReferral(
      id: json['id']?.toString() ?? json['referralId']?.toString() ?? '',
      referrerPatientId: json['referrerPatientId']?.toString() ?? json['referrer_patient_id']?.toString() ?? json['referrerId']?.toString() ?? json['referrer_id']?.toString() ?? '',
      referrerPatientName: referrerName,
      referrerPatientPhone: json['referrerPatientPhone']?.toString() ?? (json['referrer'] is Map ? json['referrer']['phone']?.toString() : '') ?? '',
      referrerPatientEmail: json['referrerPatientEmail']?.toString() ?? (json['referrer'] is Map ? json['referrer']['email']?.toString() : '') ?? '',

      referredPatientId: json['referredPatientId']?.toString() ?? json['referred_patient_id']?.toString() ?? json['referredUserId']?.toString() ?? json['referred_user_id']?.toString(),
      referredPatientName: json['referredPatientName']?.toString() ?? json['referred_patient_name']?.toString() ?? json['referredUserName']?.toString() ?? 'Referred Patient',
      referredPatientMobile: json['referredPatientMobile']?.toString() ?? json['referred_patient_mobile']?.toString() ?? json['referredUserPhone']?.toString() ?? '',
      referredPatientAge: json['referredPatientAge']?.toString() ?? json['referred_patient_age']?.toString() ?? '',
      referredPatientGender: json['referredPatientGender']?.toString() ?? json['referred_patient_gender']?.toString() ?? '',
      referredPatientCity: json['referredPatientCity']?.toString() ?? json['referred_patient_city']?.toString() ?? '',
      referredPatientPincode: json['referredPatientPincode']?.toString() ?? json['referred_patient_pincode']?.toString() ?? '',
      referredPatientLocation: json['referredPatientLocation']?.toString() ?? json['referred_patient_location']?.toString() ?? '',

      requiredSpecialist: json['requiredSpecialist']?.toString() ?? json['required_specialist']?.toString() ?? 'General Dentistry',
      clinicalComplaint: json['clinicalComplaint']?.toString() ?? json['clinical_complaint']?.toString() ?? '',

      doctorId: json['doctorId']?.toString() ?? json['doctor_id']?.toString() ?? json['assigned_doctor_id']?.toString() ?? '',
      doctorName: docName,
      doctorSpecialty: json['doctorSpecialty']?.toString() ?? (json['doctor'] is Map ? (json['doctor']['speciality'] ?? json['doctor']['specialty'])?.toString() : null) ?? '',
      doctorClinicName: json['doctorClinicName']?.toString() ?? (json['doctor'] is Map && json['doctor']['clinics'] is Map ? json['doctor']['clinics']['clinic_name']?.toString() : (json['doctor'] is Map ? json['doctor']['clinic_name']?.toString() : null)) ?? '',
      doctorCity: json['doctorCity']?.toString() ?? '',
      doctorPincode: json['doctorPincode']?.toString() ?? '',
      doctorLocation: json['doctorLocation']?.toString() ?? (json['doctor'] is Map && json['doctor']['clinics'] is Map ? json['doctor']['clinics']['location']?.toString() : '') ?? '',
      doctorLanguages: langs,

      status: json['status']?.toString() ?? json['referralStatus']?.toString() ?? 'Pending',
      rejectionReason: json['rejectionReason']?.toString() ?? json['rejection_reason']?.toString(),
      whatsappStatus: json['whatsappStatus']?.toString() ?? json['whatsapp_status']?.toString() ?? 'Pending',
      referralDate: json['referralDate'] != null
          ? DateTime.tryParse(json['referralDate'].toString()) ?? DateTime.now()
          : (json['referral_date'] != null ? DateTime.tryParse(json['referral_date'].toString()) ?? DateTime.now() : DateTime.now()),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now()),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : (json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'referrer_patient_id': referrerPatientId,
      'referrer_patient_name': referrerPatientName,
      'referred_patient_id': referredPatientId,
      'referred_patient_name': referredPatientName,
      'referred_patient_mobile': referredPatientMobile,
      'referred_patient_age': referredPatientAge,
      'referred_patient_gender': referredPatientGender,
      'referred_patient_city': referredPatientCity,
      'referred_patient_pincode': referredPatientPincode,
      'referred_patient_location': referredPatientLocation,
      'required_specialist': requiredSpecialist,
      'clinical_complaint': clinicalComplaint,
      'doctor_id': doctorId,
      'doctor_name': doctorName,
      'status': status,
      'rejection_reason': rejectionReason,
      'whatsapp_status': whatsappStatus,
      'referral_date': referralDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

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
      referrerId: json['referrerId']?.toString() ?? json['referrer_id']?.toString() ?? json['referrer_patient_id']?.toString() ?? '',
      referrerName: json['referrerName']?.toString() ?? json['referrerPatientName']?.toString() ?? '',
      referrerPhone: json['referrerPhone']?.toString() ?? json['referrerPatientPhone']?.toString() ?? '',
      referrerEmail: json['referrerEmail']?.toString() ?? json['referrerPatientEmail']?.toString() ?? '',
      referredUserId: json['referredUserId']?.toString() ?? json['referred_user_id']?.toString() ?? json['referred_patient_id']?.toString() ?? '',
      referredUserName: json['referredUserName']?.toString() ?? json['referredPatientName']?.toString() ?? 'Registered Friend',
      referredUserPhone: json['referredUserPhone']?.toString() ?? json['referredPatientMobile']?.toString() ?? '',
      referredUserEmail: json['referredUserEmail']?.toString() ?? '',
      referralCode: json['referralCode']?.toString() ?? json['referral_code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'REGISTERED',
      registrationStatus: json['registrationStatus']?.toString() ?? 'Verified Account',
      consultationStatus: json['consultationStatus']?.toString() ?? 'Pending Booking',
      assignedDoctorName: json['assignedDoctorName']?.toString() ?? json['doctorName']?.toString(),
      assignedClinicName: json['assignedClinicName']?.toString() ?? json['doctorClinicName']?.toString(),
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
