import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';
import '../models/referral_model.dart';

/// Model representing a Doctor/Dentist registered in DentaGuru platform
class DoctorModel {
  final String id;
  final String userId;
  final String name;
  final String specialty;
  final String qualification;
  final int experienceYears;
  final double rating;
  final int reviewCount;
  final String clinicName;
  final String phone;
  final String email;
  final String status; // 'Available', 'In Consultation', 'On Leave'
  final String verificationStatus; // 'VERIFIED', 'PENDING_VERIFICATION', 'REJECTED', 'SUSPENDED'
  final List<String> nextAvailableSlots;
  final String consultationFee;
  final String licenseNumber;
  final Uint8List? photoBytes;
  final String clinicAddress;
  final String pincode;
  final String city;
  final String state;
  final List<String> languages;
  final double? latitude;
  final double? longitude;
  final Map<String, String> procedureFees;

  DoctorModel({
    required this.id,
    this.userId = '',
    required this.name,
    required this.specialty,
    required this.qualification,
    required this.experienceYears,
    required this.rating,
    required this.reviewCount,
    required this.clinicName,
    required this.phone,
    required this.email,
    required this.status,
    this.verificationStatus = 'VERIFIED',
    required this.nextAvailableSlots,
    required this.consultationFee,
    this.licenseNumber = 'DEN-LIC-REG',
    this.photoBytes,
    this.clinicAddress = '',
    this.pincode = '',
    this.city = '',
    this.state = '',
    this.languages = const ['English'],
    this.latitude,
    this.longitude,
    Map<String, String>? procedureFees,
  }) : procedureFees = procedureFees ?? {
          'General Consultation': consultationFee,
          'Tooth Decay / Cavity': '\$85',
          'Root Canal': '\$180',
          'Orthodontics': '\$200',
          'Tooth Extraction': '\$110',
          'Periodontics / Gum Care': '\$95',
        };

  String getFeeForCategory(String category) {
    if (procedureFees.containsKey(category)) {
      return procedureFees[category]!;
    }
    final catLower = category.toLowerCase();
    for (final entry in procedureFees.entries) {
      final keyLower = entry.key.toLowerCase();
      if (catLower.contains(keyLower) || keyLower.contains(catLower)) {
        return entry.value;
      }
    }
    return consultationFee;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'specialty': specialty,
        'qualification': qualification,
        'experienceYears': experienceYears,
        'rating': rating,
        'reviewCount': reviewCount,
        'clinicName': clinicName,
        'phone': phone,
        'email': email,
        'status': status,
        'verificationStatus': verificationStatus,
        'nextAvailableSlots': nextAvailableSlots,
        'consultationFee': consultationFee,
        'licenseNumber': licenseNumber,
        'clinicAddress': clinicAddress,
        'pincode': pincode,
        'city': city,
        'state': state,
        'languages': languages,
        'latitude': latitude,
        'longitude': longitude,
        'procedureFees': procedureFees,
        'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
      };

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    Uint8List? bytes;
    if (json['photoBase64'] != null && json['photoBase64'].toString().isNotEmpty) {
      try {
        bytes = base64Decode(json['photoBase64']);
      } catch (_) {}
    }
    Map<String, String> pFees = {};
    if (json['procedureFees'] != null && json['procedureFees'] is Map) {
      (json['procedureFees'] as Map).forEach((k, v) => pFees[k.toString()] = v.toString());
    }

    List<String> parsedLanguages = ['English'];
    final rawLangs = json['languages'] ?? (json['users'] is Map ? json['users']['languages'] : null);
    if (rawLangs != null) {
      if (rawLangs is List) {
        parsedLanguages = rawLangs.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      } else if (rawLangs is String && rawLangs.trim().isNotEmpty) {
        parsedLanguages = rawLangs.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    if (parsedLanguages.isEmpty) {
      parsedLanguages = ['English'];
    }

    return DoctorModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? (json['users'] != null ? json['users']['id'] : '') ?? '').toString(),
      name: json['name'] ?? '',
      specialty: json['specialty'] ?? json['speciality'] ?? '',
      qualification: json['qualification'] ?? json['qualifications'] ?? 'BDS, MDS',
      experienceYears: json['experienceYears'] ?? json['experience_years'] ?? 5,
      rating: (json['rating'] ?? 5.0).toDouble(),
      reviewCount: json['reviewCount'] ?? json['reviews_count'] ?? 0,
      clinicName: json['clinicName'] ?? (json['clinics'] != null ? json['clinics']['clinic_name'] : '') ?? '',
      phone: json['phone'] ?? (json['users'] != null ? json['users']['phone'] : '') ?? '',
      email: json['email'] ?? (json['users'] != null ? json['users']['email'] : '') ?? '',
      status: json['status'] ?? json['availability_status'] ?? 'Available',
      verificationStatus: json['verification_status'] ?? json['verificationStatus'] ?? 'VERIFIED',
      nextAvailableSlots: List<String>.from(json['nextAvailableSlots'] ?? []),
      consultationFee: json['consultationFee'] ?? '\$75',
      licenseNumber: json['licenseNumber'] ?? json['license_number'] ?? 'DEN-LIC-REG',
      photoBytes: bytes,
      clinicAddress: json['clinicAddress'] ?? json['location'] ?? (json['clinics'] != null ? json['clinics']['location'] : '') ?? '',
      pincode: json['pincode'] ?? json['postal_code'] ?? (json['users'] != null ? (json['users']['pincode'] ?? '') : '') ?? '',
      city: json['city'] ?? (json['users'] != null ? (json['users']['city'] ?? '') : '') ?? '',
      state: json['state'] ?? (json['users'] != null ? (json['users']['state'] ?? '') : '') ?? '',
      languages: parsedLanguages,
      latitude: (json['latitude'] ?? json['lat'] ?? (json['users'] != null ? json['users']['latitude'] : null)) != null
          ? double.tryParse((json['latitude'] ?? json['lat'] ?? json['users']['latitude']).toString())
          : null,
      longitude: (json['longitude'] ?? json['lng'] ?? (json['users'] != null ? json['users']['longitude'] : null)) != null
          ? double.tryParse((json['longitude'] ?? json['lng'] ?? json['users']['longitude']).toString())
          : null,
      procedureFees: pFees.isNotEmpty ? pFees : null,
    );
  }

  int getLocationMatchTier(String targetState, String targetCity, String targetPincode) {
    final tState = targetState.trim().toLowerCase();
    final tCity = targetCity.trim().toLowerCase();
    final tPin = targetPincode.trim();

    final dState = state.trim().toLowerCase();
    final dCity = city.trim().toLowerCase();
    final dPin = pincode.trim();

    if (tPin.isNotEmpty && dPin.isNotEmpty && tPin == dPin) {
      return 1; // Tier 1: Same Pincode
    }

    if (tPin.isNotEmpty && dPin.isNotEmpty && RegExp(r'^\d+$').hasMatch(tPin) && RegExp(r'^\d+$').hasMatch(dPin)) {
      final diff = (int.parse(tPin) - int.parse(dPin)).abs();
      if (diff <= 5) return 2; // Tier 2: Nearby Pincode
    }

    if (tCity.isNotEmpty && dCity.isNotEmpty && (tCity == dCity || dCity.contains(tCity) || tCity.contains(dCity))) {
      return 3; // Tier 3: Same City
    }

    if (tState.isNotEmpty && dState.isNotEmpty && (tState == dState || dState.contains(tState) || tState.contains(dState))) {
      return 5; // Tier 5: Same State
    }

    return 6; // Tier 6: Other Location
  }

  String getLocationBadgeText(String targetState, String targetCity, String targetPincode) {
    final tier = getLocationMatchTier(targetState, targetCity, targetPincode);
    switch (tier) {
      case 1:
        return '✅ Same Pincode – Best Match';
      case 2:
      case 3:
        return '🟢 Same City';
      default:
        return '📍 Other Location';
    }
  }
}

/// Model representing logged-in patient profile details
class PatientProfile {
  String id;
  String name;
  String email;
  String phone;
  String age;
  String gender;
  String bloodGroup;
  String emergencyContact;
  String address;
  String city;
  String state;
  String pincode;
  List<String> languages;
  Uint8List? photoBytes;

  PatientProfile({
    this.id = '',
    this.name = '',
    this.email = '',
    this.phone = '',
    this.age = '',
    this.gender = 'Female',
    this.bloodGroup = 'O Positive (O+)',
    this.emergencyContact = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.languages = const ['English'],
    this.photoBytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'age': age,
        'gender': gender,
        'bloodGroup': bloodGroup,
        'emergencyContact': emergencyContact,
        'address': address,
        'city': city,
        'state': state,
        'pincode': pincode,
        'languages': languages,
        'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
      };

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    Uint8List? bytes;
    if (json['photoBase64'] != null && json['photoBase64'].toString().isNotEmpty) {
      try {
        bytes = base64Decode(json['photoBase64']);
      } catch (_) {}
    }

    List<String> parsedLangs = ['English'];
    final rawLangs = json['languages'];
    if (rawLangs != null) {
      if (rawLangs is List) {
        parsedLangs = rawLangs.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      } else if (rawLangs is String && rawLangs.trim().isNotEmpty) {
        parsedLangs = rawLangs.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    if (parsedLangs.isEmpty) {
      parsedLangs = ['English'];
    }

    return PatientProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      age: (json['age'] ?? json['patient_age'] ?? '').toString(),
      gender: json['gender'] ?? 'Female',
      bloodGroup: json['bloodGroup'] ?? 'O Positive (O+)',
      emergencyContact: json['emergencyContact'] ?? '',
      address: json['address'] ?? json['location'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      pincode: json['pincode'] ?? json['postal_code'] ?? '',
      languages: parsedLangs,
      photoBytes: bytes,
    );
  }
}

/// Model representing a dental problem submitted by a patient for admin review
class PatientConsultationRequest {
  final String id;
  String? patientId;
  String patientName;
  String patientPhone;
  final String problemCategory;
  final String problemDescription;
  final String symptoms;
  final String preferredLocation;
  final List<String> attachments;
  final String severity; // 'Mild', 'Moderate', 'Severe'
  final DateTime submittedAt;
  String status; // 'PENDING_ADMIN_REVIEW', 'DENTIST_SUGGESTED', 'APPOINTMENT_REQUESTED', 'CONFIRMED', 'REJECTED', 'RESCHEDULED', 'COMPLETED'
  String? assignedDoctorId;
  String? assignedDoctorName;
  String? assignedDoctorSpecialty;
  String? assignedDoctorClinic;
  String? preferredDoctorId;
  String? preferredDoctorName;
  String? preferredDoctorClinic;
  String? confirmedTimeSlot;
  String? confirmedDate;
  String? adminNotes;
  bool whatsappNotificationSent;
  final String state;
  final String city;
  final String pincode;
  final double? latitude;
  final double? longitude;

  PatientConsultationRequest({
    required this.id,
    this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.problemCategory,
    required this.problemDescription,
    this.symptoms = '',
    this.preferredLocation = '',
    this.state = '',
    this.city = '',
    this.pincode = '',
    this.latitude,
    this.longitude,
    this.attachments = const [],
    required this.severity,
    required this.submittedAt,
    this.status = 'PENDING_ADMIN_REVIEW',
    this.assignedDoctorId,
    this.assignedDoctorName,
    this.assignedDoctorSpecialty,
    this.assignedDoctorClinic,
    this.preferredDoctorId,
    this.preferredDoctorName,
    this.preferredDoctorClinic,
    this.confirmedTimeSlot,
    this.confirmedDate,
    this.adminNotes,
    this.whatsappNotificationSent = false,
  });

  String getDisplayCity(List<PatientProfile> allPatients) {
    if (city.trim().isNotEmpty) return city.trim();
    if (allPatients.isNotEmpty) {
      final match = allPatients.firstWhere(
        (p) => (patientId != null && patientId!.isNotEmpty && p.id == patientId) ||
               (p.name.isNotEmpty && patientName.isNotEmpty && p.name.trim().toLowerCase() == patientName.trim().toLowerCase()) ||
               (p.phone.isNotEmpty && patientPhone.isNotEmpty && p.phone.trim() == patientPhone.trim()),
        orElse: () => PatientProfile(),
      );
      if (match.city.trim().isNotEmpty) return match.city.trim();
    }
    return 'Not Available';
  }

  String getDisplayPincode(List<PatientProfile> allPatients) {
    if (pincode.trim().isNotEmpty) return pincode.trim();
    if (allPatients.isNotEmpty) {
      final match = allPatients.firstWhere(
        (p) => (patientId != null && patientId!.isNotEmpty && p.id == patientId) ||
               (p.name.isNotEmpty && patientName.isNotEmpty && p.name.trim().toLowerCase() == patientName.trim().toLowerCase()) ||
               (p.phone.isNotEmpty && patientPhone.isNotEmpty && p.phone.trim() == patientPhone.trim()),
        orElse: () => PatientProfile(),
      );
      if (match.pincode.trim().isNotEmpty) return match.pincode.trim();
    }
    return '';
  }

  String get displayDoctorName {
    if (assignedDoctorName != null &&
        assignedDoctorName!.trim().isNotEmpty &&
        assignedDoctorName != 'null' &&
        assignedDoctorName != 'Dr. Specialist') {
      return assignedDoctorName!;
    }
    if (assignedDoctorId != null && assignedDoctorId!.isNotEmpty) {
      final doc = PatientProblemService().allDoctors.firstWhere(
        (d) =>
            d.id == assignedDoctorId ||
            d.email.toLowerCase() == assignedDoctorId!.toLowerCase() ||
            (d.name.isNotEmpty && assignedDoctorId!.toLowerCase().contains(d.name.replaceAll('Dr. ', '').trim().toLowerCase())),
        orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
      );
      if (doc.name.isNotEmpty) return doc.name;
    }
    final docs = PatientProblemService().allDoctors;
    if (docs.isNotEmpty) {
      return docs.first.name;
    }
    return 'Dr. Rahul Sharma';
  }

  String get displayDoctorSpecialty {
    if (assignedDoctorSpecialty != null &&
        assignedDoctorSpecialty!.trim().isNotEmpty &&
        assignedDoctorSpecialty != 'null' &&
        assignedDoctorSpecialty != 'Dental Specialist') {
      return assignedDoctorSpecialty!;
    }
    if (assignedDoctorId != null && assignedDoctorId!.isNotEmpty) {
      final doc = PatientProblemService().allDoctors.firstWhere(
        (d) =>
            d.id == assignedDoctorId ||
            d.email.toLowerCase() == assignedDoctorId!.toLowerCase() ||
            (d.name.isNotEmpty && assignedDoctorId!.toLowerCase().contains(d.name.replaceAll('Dr. ', '').trim().toLowerCase())),
        orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
      );
      if (doc.specialty.isNotEmpty) return doc.specialty;
    }
    final docs = PatientProblemService().allDoctors;
    if (docs.isNotEmpty) {
      return docs.first.specialty;
    }
    return 'Orthodontics & Dental Surgery';
  }

  String get displayDoctorClinic {
    if (assignedDoctorClinic != null &&
        assignedDoctorClinic!.trim().isNotEmpty &&
        assignedDoctorClinic != 'null') {
      return assignedDoctorClinic!;
    }
    return 'DentaGuru Care Center';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'patient_id': patientId,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'problemCategory': problemCategory,
        'problemDescription': problemDescription,
        'symptoms': symptoms,
        'preferredLocation': preferredLocation,
        'state': state,
        'city': city,
        'pincode': pincode,
        'latitude': latitude,
        'longitude': longitude,
        'attachments': attachments,
        'severity': severity,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status,
        'assignedDoctorId': assignedDoctorId,
        'assignedDoctorName': assignedDoctorName,
        'assignedDoctorSpecialty': assignedDoctorSpecialty,
        'assignedDoctorClinic': assignedDoctorClinic,
        'preferredDoctorId': preferredDoctorId,
        'preferredDoctorName': preferredDoctorName,
        'preferredDoctorClinic': preferredDoctorClinic,
        'confirmedTimeSlot': confirmedTimeSlot,
        'confirmedDate': confirmedDate,
        'adminNotes': adminNotes,
        'whatsappNotificationSent': whatsappNotificationSent,
      };

  factory PatientConsultationRequest.fromJson(Map<String, dynamic> json) {
    final patientObj = json['patient'] is Map ? json['patient'] : {};
    final desc = (json['problemDescription'] ?? json['problem_description'] ?? '').toString();

    String? prefDocName = (json['preferredDoctorName'] ?? json['preferred_doctor_name'])?.toString();
    String? prefDocClinic = (json['preferredDoctorClinic'] ?? json['preferred_doctor_clinic'])?.toString();
    if (prefDocName == null && desc.contains('Patient referred/recommended to ')) {
      try {
        final start = desc.indexOf('Patient referred/recommended to ') + 'Patient referred/recommended to '.length;
        final end = desc.indexOf('(', start);
        if (end > start) {
          prefDocName = desc.substring(start, end).trim();
        }
        final clinicStart = desc.indexOf('(', start) + 1;
        final clinicEnd = desc.indexOf(')', clinicStart);
        if (clinicEnd > clinicStart) {
          prefDocClinic = desc.substring(clinicStart, clinicEnd).trim();
        }
      } catch (_) {}
    }

    final rawAssignedName = json['assignedDoctorName'] ?? json['suggested_dentist']?['users']?['name'];
    final assignedNameClean = (rawAssignedName != null && rawAssignedName.toString() != 'null' && rawAssignedName.toString().trim().isNotEmpty)
        ? rawAssignedName.toString().trim()
        : null;

    final rawStatus = (json['status'] ?? 'PENDING_ADMIN_REVIEW').toString();

    return PatientConsultationRequest(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      patientId: (json['patientId'] ?? json['patient_id'] ?? patientObj['id'])?.toString(),
      patientName: json['patientName'] ?? json['patient_name'] ?? (patientObj['name'] ?? ''),
      patientPhone: json['patientPhone'] ?? json['patient_phone'] ?? (patientObj['phone'] ?? ''),
      problemCategory: json['problemCategory'] ?? json['problem_category'] ?? '',
      problemDescription: json['problemDescription'] ?? json['problem_description'] ?? '',
      symptoms: json['symptoms'] ?? '',
      preferredLocation: json['preferredLocation'] ?? json['preferred_location'] ?? '',
      state: json['state'] ?? (patientObj['state'] ?? ''),
      city: json['city'] ?? (patientObj['city'] ?? ''),
      pincode: json['pincode'] ?? (patientObj['pincode'] ?? ''),
      latitude: (json['latitude'] ?? patientObj['latitude']) != null ? double.tryParse((json['latitude'] ?? patientObj['latitude']).toString()) : null,
      longitude: (json['longitude'] ?? patientObj['longitude']) != null ? double.tryParse((json['longitude'] ?? patientObj['longitude']).toString()) : null,
      attachments: List<String>.from(json['attachments'] ?? []),
      severity: json['severity'] ?? 'Moderate',
      submittedAt: json['submittedAt'] != null 
          ? DateTime.parse(json['submittedAt']) 
          : (json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now()),
      status: rawStatus,
      assignedDoctorId: (json['assignedDoctorId'] ?? json['suggested_dentist_id'])?.toString(),
      assignedDoctorName: assignedNameClean,
      assignedDoctorSpecialty: json['assignedDoctorSpecialty'] ?? json['suggested_dentist']?['speciality'],
      assignedDoctorClinic: json['assignedDoctorClinic'] ?? json['suggested_dentist']?['clinics']?['clinic_name'],
      preferredDoctorId: (json['preferredDoctorId'] ?? json['preferred_doctor_id'])?.toString(),
      preferredDoctorName: prefDocName,
      preferredDoctorClinic: prefDocClinic,
      confirmedTimeSlot: json['confirmedTimeSlot'],
      confirmedDate: json['confirmedDate'],
      adminNotes: json['adminNotes'] ?? json['admin_notes'],
      whatsappNotificationSent: json['whatsappNotificationSent'] ?? false,
    );
  }
}

/// Central state service for logged in patient, consultation requests, and doctor directory
/// Model representing a Clinic registered in DentaGuru platform
class ClinicModel {
  final String id;
  final String clinicName;
  final String location;
  final double rating;
  final int reviewsCount;
  final bool verified;
  final String verificationStatus; // 'VERIFIED', 'PENDING_VERIFICATION', 'REJECTED', 'SUSPENDED'
  final List<String> services;
  final List<Map<String, dynamic>> pricing;

  ClinicModel({
    required this.id,
    required this.clinicName,
    required this.location,
    this.rating = 5.0,
    this.reviewsCount = 0,
    this.verified = true,
    this.verificationStatus = 'VERIFIED',
    List<String>? services,
    List<Map<String, dynamic>>? pricing,
  })  : services = services ?? ['Teeth Cleaning', 'Root Canal', 'Orthodontics'],
        pricing = pricing ?? [];

  factory ClinicModel.fromJson(Map<String, dynamic> json) {
    List<String> servList = [];
    if (json['services'] is List) {
      servList = (json['services'] as List).map((s) => s.toString()).toList();
    }
    List<Map<String, dynamic>> priceList = [];
    if (json['pricing'] is List) {
      priceList = (json['pricing'] as List).map((p) => p is Map<String, dynamic> ? p : <String, dynamic>{}).toList();
    }
    return ClinicModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      clinicName: (json['clinic_name'] ?? json['clinicName'] ?? 'DentaGuru Care Center').toString(),
      location: (json['location'] ?? '123 Healthcare Blvd').toString(),
      rating: (json['rating'] ?? 5.0).toDouble(),
      reviewsCount: json['reviews_count'] ?? json['reviewsCount'] ?? 0,
      verified: json['verified'] ?? true,
      verificationStatus: json['verification_status'] ?? json['verificationStatus'] ?? 'VERIFIED',
      services: servList,
      pricing: priceList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clinicName': clinicName,
        'location': location,
        'rating': rating,
        'reviewsCount': reviewsCount,
        'verified': verified,
        'verificationStatus': verificationStatus,
        'services': services,
        'pricing': pricing,
      };
}

/// Model representing an In-App Notification for Patient, Dentist, or Admin
class AppNotificationModel {
  final String id;
  final String recipientRole; // 'Patient', 'Dentist', 'Admin'
  final String recipientId;
  final String title;
  final String message;
  final DateTime timestamp;
  bool isRead;

  AppNotificationModel({
    required this.id,
    required this.recipientRole,
    required this.recipientId,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipientRole': recipientRole,
        'recipientId': recipientId,
        'title': title,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory AppNotificationModel.fromJson(Map<String, dynamic> json) => AppNotificationModel(
        id: json['id'] ?? '',
        recipientRole: json['recipientRole'] ?? 'Patient',
        recipientId: json['recipientId'] ?? '',
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
        isRead: json['isRead'] ?? false,
      );
}

class PatientProblemService extends ChangeNotifier {
  static final PatientProblemService _instance = PatientProblemService._internal();
  factory PatientProblemService() => _instance;

  PatientProblemService._internal() {
    _loadFromStorage();
  }

  // Admin Mode state flag
  bool _isAdminMode = false;
  bool get isAdminMode => _isAdminMode;

  void setAdminMode(bool enabled) {
    _isAdminMode = enabled;
    syncProblemRequestsFromApi();
  }

  // Current Logged-in Patient Profile
  PatientProfile currentPatient = PatientProfile();

  // In-memory cache for user profile photos across sessions
  final Map<String, Uint8List> _userPhotoCache = {};

  // Current Logged-in Doctor Profile
  DoctorModel? currentDoctor;

  // Directory of All Doctors in the Platform
  final List<DoctorModel> _allDoctors = [];

  List<DoctorModel> get allDoctors => List.unmodifiable(_allDoctors);

  // Directory of All Clinics in the Platform
  final List<ClinicModel> _allClinics = [];

  List<ClinicModel> get allClinics => List.unmodifiable(_allClinics);

  // List of Consultation Requests
  final List<PatientConsultationRequest> _requests = [];

  List<PatientConsultationRequest> get requests => List.unmodifiable(_requests);

  // List of Consultation Requests Assigned to Logged-In Dentist
  final List<PatientConsultationRequest> _dentistAssignedRequests = [];

  List<PatientConsultationRequest> get dentistAssignedRequests => List.unmodifiable(_dentistAssignedRequests);

  Future<void> deleteProblemRequest(String id) async {
    _requests.removeWhere((r) => r.id == id);
    _saveToStorage();
    notifyListeners();
    try {
      await ApiService().deleteProblemRequest(id);
    } catch (e) {
      debugPrint('Error deleting problem request: $e');
    }
  }

  // List of In-App Notifications
  final List<AppNotificationModel> _appNotifications = [];

  List<AppNotificationModel> get appNotifications => List.unmodifiable(_appNotifications);

  void addNotification({
    required String recipientRole,
    required String recipientId,
    required String title,
    required String message,
  }) {
    final notif = AppNotificationModel(
      id: 'NOTIF-${DateTime.now().millisecondsSinceEpoch}',
      recipientRole: recipientRole,
      recipientId: recipientId,
      title: title,
      message: message,
      timestamp: DateTime.now(),
    );
    _appNotifications.insert(0, notif);
    _saveToStorage();
    notifyListeners();
  }

  // List of Issued Medical Records / Prescriptions
  final List<Map<String, dynamic>> _medicalRecords = [];

  List<Map<String, dynamic>> get medicalRecords => List.unmodifiable(_medicalRecords);

  void addMedicalRecord(Map<String, dynamic> record) {
    _medicalRecords.insert(0, record);
    _saveToStorage();
    notifyListeners();
  }

  // Master Registered Patients List from Supabase DB
  final List<PatientProfile> _allPatients = [];

  List<PatientProfile> get allPatients => List.unmodifiable(_allPatients);

  // ----------------------------------------------------
  // Persistent SharedPreferences Storage Methods
  // ----------------------------------------------------
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Load Patient Profile
      final pStr = prefs.getString('dentaguru_patient_profile');
      if (pStr != null && pStr.isNotEmpty) {
        currentPatient = PatientProfile.fromJson(jsonDecode(pStr));
      }

      // 2. Load Doctor Profile scoped to authenticated email
      final authEmail = Supabase.instance.client.auth.currentUser?.email?.trim().toLowerCase();
      String? dStr;
      if (authEmail != null && authEmail.isNotEmpty) {
        dStr = prefs.getString('dentaguru_current_doctor_$authEmail');
      }
      dStr ??= prefs.getString('dentaguru_current_doctor');

      if (dStr != null && dStr.isNotEmpty) {
        final parsedDoc = DoctorModel.fromJson(jsonDecode(dStr));
        if (authEmail == null || parsedDoc.email.trim().toLowerCase() == authEmail) {
          currentDoctor = parsedDoc;
        }
      }

      // 3. Load Consultation Requests
      final reqStr = prefs.getString('dentaguru_requests');
      if (reqStr != null && reqStr.isNotEmpty) {
        final List list = jsonDecode(reqStr);
        _requests.clear();
        for (final item in list) {
          _requests.add(PatientConsultationRequest.fromJson(item));
        }
      }

      // 3b. Load Dentist Assigned Requests
      final dReqStr = prefs.getString('dentaguru_dentist_assigned_requests');
      if (dReqStr != null && dReqStr.isNotEmpty) {
        final List list = jsonDecode(dReqStr);
        _dentistAssignedRequests.clear();
        for (final item in list) {
          _dentistAssignedRequests.add(PatientConsultationRequest.fromJson(item));
        }
      }

      // 4. Load Medical Records
      final medStr = prefs.getString('dentaguru_medical_records');
      if (medStr != null && medStr.isNotEmpty) {
        final List list = jsonDecode(medStr);
        _medicalRecords.clear();
        _medicalRecords.addAll(List<Map<String, dynamic>>.from(list));
      }

      // 5. Load Master Patients List
      final patStr = prefs.getString('dentaguru_all_patients');
      if (patStr != null && patStr.isNotEmpty) {
        final List list = jsonDecode(patStr);
        _allPatients.clear();
        for (final item in list) {
          final p = PatientProfile.fromJson(item);
          if (!p.email.toLowerCase().contains('admin')) {
            _allPatients.add(p);
          }
        }
      }

      // 5b. Load Sub-Admin Session
      final subAdminSessionStr = prefs.getString('dentaguru_sub_admin_session');
      if (subAdminSessionStr != null && subAdminSessionStr.isNotEmpty) {
        try {
          final Map<String, dynamic> saMap = jsonDecode(subAdminSessionStr);
          _isSubAdminMode = saMap['isSubAdminMode'] == true;
          _subAdminId = (saMap['id'] ?? '').toString();
          _subAdminName = (saMap['name'] ?? '').toString();
          _subAdminEmail = (saMap['email'] ?? '').toString();
          _subAdminPhone = (saMap['phone'] ?? '').toString();
          _subAdminStatus = (saMap['status'] ?? 'ACTIVE').toString();
          _subAdminPermissions.clear();
          if (saMap['permissions'] is List) {
            for (final p in saMap['permissions']) {
              if (p != null && p.toString().trim().isNotEmpty) {
                _subAdminPermissions.add(p.toString().trim().toUpperCase());
              }
            }
          }
        } catch (_) {}
      }

      // 6. Sync live patients, appointments, clinics, doctors, records, and requests directly from Supabase DB API
      syncAllDataFromApi();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading PatientProblemService state from storage: $e');
    }
  }

  final List<Map<String, dynamic>> _subAdmins = [];
  List<Map<String, dynamic>> get subAdmins => List.unmodifiable(_subAdmins);

  // Sub-Admin RBAC Session State
  bool _isSubAdminMode = false;
  final Set<String> _subAdminPermissions = {};
  String _subAdminStatus = 'ACTIVE';
  String _subAdminName = '';
  String _subAdminEmail = '';
  String _subAdminPhone = '';
  String _subAdminId = '';

  bool get isSubAdminMode => _isSubAdminMode;
  Set<String> get subAdminPermissions => Set.unmodifiable(_subAdminPermissions);
  String get subAdminStatus => _subAdminStatus;
  String get subAdminName => _subAdminName;
  String get subAdminEmail => _subAdminEmail;
  String get subAdminPhone => _subAdminPhone;
  String get subAdminId => _subAdminId;

  bool hasPermission(String permission) {
    if (!_isSubAdminMode) return true; // Primary admin has full access
    if (_subAdminStatus == 'INACTIVE' || _subAdminStatus == 'DEACTIVATED') return false;
    final pUpper = permission.trim().toUpperCase();
    return _subAdminPermissions.contains('*') ||
           _subAdminPermissions.contains('ALL') ||
           _subAdminPermissions.contains(pUpper);
  }

  void setSubAdminSession({
    required String id,
    required String name,
    required String email,
    required String phone,
    required List<String> permissions,
    String status = 'ACTIVE',
  }) {
    _isSubAdminMode = true;
    _subAdminId = id.trim();
    _subAdminName = name.trim();
    _subAdminEmail = email.trim();
    _subAdminPhone = phone.trim();
    _subAdminStatus = status.trim().toUpperCase();
    _subAdminPermissions.clear();
    for (final p in permissions) {
      if (p.trim().isNotEmpty) {
        _subAdminPermissions.add(p.trim().toUpperCase());
      }
    }
    _saveToStorage();
    notifyListeners();
  }

  void clearSubAdminSession() {
    _isSubAdminMode = false;
    _subAdminId = '';
    _subAdminName = '';
    _subAdminEmail = '';
    _subAdminPhone = '';
    _subAdminStatus = 'ACTIVE';
    _subAdminPermissions.clear();
    _saveToStorage();
    notifyListeners();
  }

  Future<void> syncAllDataFromApi() async {
    try {
      await Future.wait([
        syncPatientsFromApi(),
        syncClinicsFromApi(),
        syncDoctorsFromApi(),
        syncMedicalRecordsFromApi(),
        syncSubAdminsFromApi(),
      ]);
      await Future.wait([
        syncAppointmentsFromApi(),
        syncProblemRequestsFromApi(),
        syncDentistAssignedRequestsFromApi(),
        syncReferralsFromApi(),
        syncAdminReferralsFromApi(),
      ]);
    } catch (e) {
      debugPrint('Error in syncAllDataFromApi: $e');
    }
  }

  Future<void> syncSubAdminsFromApi() async {
    try {
      final list = await ApiService().fetchSubAdmins();
      _subAdmins.clear();
      if (list.isNotEmpty) {
        for (final item in list) {
          _subAdmins.add(Map<String, dynamic>.from(item));
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Sync sub-admins error: $e');
    }
  }

  Future<bool> registerSubAdmin({
    required String name,
    required String phone,
    String? email,
    String? password,
    String? city,
    String? pincode,
    List<String>? languages,
    List<String>? permissions,
    String status = 'ACTIVE',
  }) async {
    try {
      final res = await ApiService().createSubAdmin(
        name: name,
        phone: phone,
        email: email,
        password: password,
        city: city,
        pincode: pincode,
        languages: languages,
        permissions: permissions,
        status: status,
      );
      if (res['success'] == true) {
        await syncSubAdminsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('registerSubAdmin error: $e');
    }
    return false;
  }

  void updateSubAdminStatusLocally(String id, String status) {
    final idx = _subAdmins.indexWhere((s) => (s['id'] ?? '').toString() == id);
    if (idx != -1) {
      _subAdmins[idx]['status'] = status;
      notifyListeners();
    }
  }

  void removeSubAdminLocally(String id) {
    _subAdmins.removeWhere((s) => (s['id'] ?? '').toString() == id);
    notifyListeners();
  }

  Future<void> clearAllDataAndStorage() async {
    _requests.clear();
    _dentistAssignedRequests.clear();
    _medicalRecords.clear();
    _allPatients.clear();
    _allDoctors.clear();
    _allClinics.clear();
    _appNotifications.clear();
    currentPatient = PatientProfile();
    currentDoctor = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> syncPatientsFromApi() async {
    try {
      final list = await ApiService().fetchPatients();
      _allPatients.clear();
      if (list.isNotEmpty) {
        for (final item in list) {
          final id = (item['id'] ?? '').toString();
          String name = (item['name'] ?? '').toString().trim();
          final email = (item['email'] ?? '').toString().trim();
          final phone = (item['phone'] ?? '').toString().trim();
          final role = (item['role'] ?? '').toString().trim().toLowerCase();

          Map<String, dynamic> tokenMeta = {};
          final devToken = (item['device_token'] ?? item['biometric_token'] ?? '').toString().trim();
          if (devToken.startsWith('{') && devToken.endsWith('}')) {
            try {
              tokenMeta = jsonDecode(devToken);
            } catch (_) {}
          }

          final rawAge = (item['age'] ?? item['patient_age'] ?? tokenMeta['age'] ?? '').toString().trim();
          final age = (rawAge.isNotEmpty && rawAge != 'null') ? rawAge : '';
          final rawBlood = (item['bloodGroup'] ?? item['blood_group'] ?? tokenMeta['bloodGroup'] ?? tokenMeta['blood_group'] ?? '').toString().trim();
          final bloodGroup = (rawBlood.isNotEmpty && rawBlood != 'null') ? rawBlood : 'O Positive (O+)';
          final rawGender = (item['gender'] ?? tokenMeta['gender'] ?? '').toString().trim();
          final gender = (rawGender.isNotEmpty && rawGender != 'null') ? rawGender : 'Female';
          final emergencyContact = (item['emergency_contact'] ?? item['emergencyContact'] ?? tokenMeta['emergencyContact'] ?? '').toString().trim();

          final city = (item['city'] ?? tokenMeta['city'] ?? item['location_city'] ?? '').toString();
          final pincode = (item['pincode'] ?? tokenMeta['pincode'] ?? item['postal_code'] ?? '').toString();
          final state = (item['state'] ?? tokenMeta['state'] ?? '').toString();
          final address = (item['address'] ?? tokenMeta['address'] ?? item['location'] ?? '').toString();

          final isActualAdmin = (email.toLowerCase() == 'anusripvc202@gmail.com') || (role.contains('admin') && !email.contains('patient'));
          if (isActualAdmin) {
            continue; // Skip only actual admin accounts
          }

          if (name.isEmpty && email.isNotEmpty) {
            name = email.split('@').first;
          }
          if (name.isEmpty) {
            name = 'Patient';
          }

          List<String> userLangs = ['English'];
          final rawLangs = item['languages'] ?? tokenMeta['languages'];
          if (rawLangs != null) {
            if (rawLangs is List) {
              userLangs = rawLangs.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
            } else if (rawLangs is String && rawLangs.trim().isNotEmpty) {
              userLangs = rawLangs.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            }
          }
          if (userLangs.isEmpty) userLangs = ['English'];

          final pProfile = PatientProfile(
            id: id,
            name: name,
            email: email,
            phone: phone,
            age: age,
            gender: gender,
            bloodGroup: bloodGroup,
            emergencyContact: emergencyContact,
            city: city,
            pincode: pincode,
            state: state,
            address: address,
            languages: userLangs,
          );
          _allPatients.add(pProfile);

          final authEmail = Supabase.instance.client.auth.currentUser?.email;
          final isCurrentPatientMatch = (authEmail != null && authEmail.isNotEmpty && authEmail.toLowerCase() == email.toLowerCase()) ||
              (currentPatient.email.isNotEmpty && currentPatient.email.toLowerCase() == email.toLowerCase()) ||
              (currentPatient.id.isNotEmpty && currentPatient.id == id);

          if (isCurrentPatientMatch) {
            currentPatient.id = id;
            if (name.isNotEmpty) currentPatient.name = name;
            if (email.isNotEmpty) currentPatient.email = email;
            if (phone.isNotEmpty) currentPatient.phone = phone;
            if (age.isNotEmpty) {
              currentPatient.age = age;
            }
            if (bloodGroup.isNotEmpty && (currentPatient.bloodGroup == 'O Positive (O+)' || currentPatient.bloodGroup.isEmpty)) {
              currentPatient.bloodGroup = bloodGroup;
            }
            if (gender.isNotEmpty) currentPatient.gender = gender;
            if (emergencyContact.isNotEmpty) currentPatient.emergencyContact = emergencyContact;
            if (city.isNotEmpty) currentPatient.city = city;
            if (pincode.isNotEmpty) currentPatient.pincode = pincode;
            if (state.isNotEmpty) currentPatient.state = state;
            if (address.isNotEmpty) currentPatient.address = address;
            if (userLangs.isNotEmpty) currentPatient.languages = userLangs;
          }
        }
      }
      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync patients error: $e');
    }
  }

  Future<void> syncMedicalRecordsFromApi() async {
    try {
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : null;
      final apiRecords = await ApiService().fetchMedicalRecords(patientId: pId);
      if (apiRecords.isNotEmpty) {
        final existingIds = _medicalRecords.map((r) => r['id']?.toString() ?? '').toSet();
        for (final item in apiRecords) {
          final itemMap = Map<String, dynamic>.from(item);
          final id = itemMap['id']?.toString() ?? '';
          if (id.isNotEmpty && !existingIds.contains(id)) {
            _medicalRecords.insert(0, itemMap);
          } else if (id.isEmpty) {
            _medicalRecords.insert(0, itemMap);
          }
        }
        _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync medical records error: $e');
    }
  }

  bool _isDentistMode = false;
  void setDentistMode(bool enabled) {
    _isDentistMode = enabled;
    if (enabled) {
      syncProblemRequestsFromApi();
    }
  }

  Future<void> syncProblemRequestsFromApi() async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : authUser?.id;
      final pEmail = currentPatient.email.isNotEmpty ? currentPatient.email : authUser?.email;
      final currentPName = currentPatient.name;

      final isAdmin = _isAdminMode ||
                      (authUser?.email != null && (authUser!.email!.toLowerCase().contains('admin') || authUser.email!.toLowerCase() == 'anusripvc202@gmail.com')) ||
                      currentPatient.email.toLowerCase().contains('admin') ||
                      currentPatient.id.toLowerCase().contains('admin');

      final List problemReqs = isAdmin
          ? await ApiService().fetchAdminProblemRequests()
          : (_isDentistMode
              ? await ApiService().fetchDentistAssignedRequests(
                  dentistId: currentDoctor?.id.isNotEmpty == true ? currentDoctor!.id : currentDoctor?.userId,
                  dentistName: currentDoctor?.name,
                )
              : await ApiService().fetchPatientProblemRequests(patientId: pId));

      if (problemReqs.isEmpty) {
        return;
      }

      for (final pr in problemReqs) {
        final prId = (pr['_id'] ?? pr['id'] ?? '').toString();
        if (prId.isEmpty) continue;
        final reqPatientId = (pr['patient_id'] ?? pr['patientId'] ?? pr['patient']?['id'])?.toString() ?? '';

        // ✅ If Dentist mode, enforce strict dentist ownership verification
        if (_isDentistMode) {
          final assignedDocId = (pr['assigned_doctor_id'] ?? pr['suggested_dentist_id'] ?? pr['dentist']?['id'])?.toString();
          final assignedDocName = (pr['assigned_doctor_name'] ?? pr['assignedDoctorName'] ?? pr['dentist']?['name'])?.toString();
          final myId = currentDoctor?.id ?? '';
          final myUserId = currentDoctor?.userId ?? '';
          final myEmail = currentDoctor?.email.toLowerCase() ?? '';
          final myName = (currentDoctor?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();

          bool isForMe = false;
          if (myId.isNotEmpty && assignedDocId == myId) isForMe = true;
          if (myUserId.isNotEmpty && assignedDocId == myUserId) isForMe = true;
          if (myEmail.isNotEmpty && assignedDocId?.toLowerCase() == myEmail) isForMe = true;
          if (myName.isNotEmpty && myName != 'dentist' && assignedDocName != null && assignedDocName.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase() == myName) isForMe = true;

          if (!isForMe) {
            continue; // Skip records not assigned to this specific doctor!
          }
        }

        // ✅ If NOT admin and NOT dentist, enforce strict patient ownership verification
        if (!isAdmin && !_isDentistMode) {
          final reqPatientEmail = (pr['patient_email'] ?? pr['patientEmail'] ?? pr['patient']?['email'])?.toString() ?? '';
          final reqPatientName = (pr['patient_name'] ?? pr['patientName'] ?? pr['patient']?['name'])?.toString() ?? '';

          bool isMine = false;
          if (pId != null && pId.isNotEmpty && (reqPatientId == pId || reqPatientId.contains(pId))) isMine = true;
          if (pEmail != null && pEmail.isNotEmpty && (reqPatientEmail.toLowerCase() == pEmail.toLowerCase() || reqPatientId.toLowerCase() == pEmail.toLowerCase())) isMine = true;
          if (currentPName.isNotEmpty && currentPName != 'Patient' && reqPatientName.trim().toLowerCase() == currentPName.trim().toLowerCase()) isMine = true;

          // Reject records belonging to another patient
          if (!isMine && (pId != null || pEmail != null || (currentPName.isNotEmpty && currentPName != 'Patient'))) {
            continue;
          }
        }
        final category = (pr['problem_category'] ?? pr['problemCategory'] ?? 'Dental Issue').toString();
        final desc = (pr['problem_description'] ?? pr['problemDescription'] ?? '').toString();
        final rawStatus = (pr['status'] ?? 'SUBMITTED').toString();
        final severity = (pr['severity'] ?? 'Moderate').toString();
        final adminNotes = pr['admin_notes']?.toString() ?? pr['adminNotes']?.toString();
        String? confirmedSlot = pr['confirmed_time_slot']?.toString() ?? pr['confirmedTimeSlot']?.toString();
        final symptoms = (pr['symptoms'] ?? '').toString();
        final preferredLocation = (pr['preferred_location'] ?? pr['preferredLocation'] ?? '').toString();
        final patientObj = pr['patient'] is Map ? pr['patient'] : {};
        final dentistObj = pr['dentist'] is Map ? pr['dentist'] : {};

        final city = (pr['city'] != null && pr['city'].toString().isNotEmpty
                ? pr['city']
                : (patientObj['city'] ?? ''))
            .toString();
        final pincode = (pr['pincode'] != null && pr['pincode'].toString().isNotEmpty
                ? pr['pincode']
                : (patientObj['pincode'] ?? ''))
            .toString();
        final state = (pr['state'] != null && pr['state'].toString().isNotEmpty
                ? pr['state']
                : (patientObj['state'] ?? ''))
            .toString();

        final assignedDocId = (pr['assigned_doctor_id'] ?? pr['suggested_dentist_id'] ?? dentistObj['id'])?.toString();
        String? assignedDocName = (pr['assigned_doctor_name'] ?? pr['assignedDoctorName'] ?? dentistObj['name'])?.toString();
        String? assignedDocSpecialty = (pr['assigned_doctor_specialty'] ?? pr['assignedDoctorSpecialty'] ?? dentistObj['speciality'] ?? dentistObj['specialty'])?.toString();
        String? assignedDocClinic = (pr['assigned_doctor_clinic'] ?? pr['assignedDoctorClinic'] ?? dentistObj['clinicName'])?.toString();

        if ((assignedDocName == null || assignedDocName.isEmpty || assignedDocName == 'null' || assignedDocName == 'Dr. Specialist') && dentistObj.isNotEmpty) {
          final dUser = dentistObj['users'] is Map ? dentistObj['users'] : (dentistObj['user'] is Map ? dentistObj['user'] : {});
          final dClinic = dentistObj['clinics'] is Map ? dentistObj['clinics'] : (dentistObj['clinic'] is Map ? dentistObj['clinic'] : {});
          if (dUser['name'] != null && dUser['name'].toString().isNotEmpty) {
            final dn = dUser['name'].toString().trim();
            assignedDocName = dn.startsWith('Dr.') ? dn : 'Dr. $dn';
          }
          if (dentistObj['speciality'] != null && dentistObj['speciality'].toString().isNotEmpty) {
            assignedDocSpecialty = dentistObj['speciality'].toString().trim();
          }
          if (dClinic['clinic_name'] != null && dClinic['clinic_name'].toString().isNotEmpty) {
            assignedDocClinic = dClinic['clinic_name'].toString().trim();
          }
        }

        if (assignedDocName == null || assignedDocName.isEmpty || assignedDocName == 'null' || assignedDocName == 'Dr. Specialist') {
          if (assignedDocId != null && assignedDocId.isNotEmpty) {
            final matchedDoc = _allDoctors.firstWhere(
              (d) => d.id == assignedDocId || d.email == assignedDocId || (d.name.isNotEmpty && (assignedDocId == d.name || assignedDocId.contains(d.name.replaceAll('Dr. ', '').trim()))),
              orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
            );
            if (matchedDoc.name.isNotEmpty) {
              assignedDocName = matchedDoc.name;
              assignedDocSpecialty = matchedDoc.specialty;
              assignedDocClinic = matchedDoc.clinicName;
            }
          }
        }

        if (assignedDocName == null || assignedDocName == 'null') {
          assignedDocName = '';
        }

        // Normalize status from DB to frontend display values
        final rawStatusUpper = rawStatus.toUpperCase();
        String normalizedStatus;
        if (rawStatusUpper == 'CONFIRMED' ||
            rawStatusUpper == 'ACCEPTED' ||
            rawStatusUpper == 'DENTIST_ACCEPTED') {
          normalizedStatus = 'Confirmed';
        } else if (rawStatusUpper == 'DENTIST_ASSIGNED' ||
            rawStatusUpper == 'DENTIST_SUGGESTED' ||
            rawStatusUpper == 'PENDING_DENTIST_CONFIRMATION' ||
            (assignedDocName.isNotEmpty)) {
          normalizedStatus = 'Doctor Assigned';
        } else if (rawStatusUpper == 'ADMIN_REVIEWED' || rawStatusUpper == 'ADMIN_REVIEW') {
          normalizedStatus = 'Admin Review';
        } else {
          normalizedStatus = 'Submitted'; // SUBMITTED / PENDING_ADMIN_REVIEW / anything else
        }

        String pName = (pr['patientName'] ?? pr['patient_name'] ?? patientObj['name'] ?? '').toString().trim();
        String pPhone = (pr['patientPhone'] ?? pr['patient_phone'] ?? patientObj['phone'] ?? '').toString().trim();

        if (pName.isEmpty || pName.toLowerCase() == 'patient') {
          if (reqPatientId.isNotEmpty) {
            final matchById = _allPatients.firstWhere(
              (p) => p.id == reqPatientId,
              orElse: () => PatientProfile(name: ''),
            );
            if (matchById.name.isNotEmpty && matchById.name.toLowerCase() != 'patient') {
              pName = matchById.name;
              if (pPhone.isEmpty) pPhone = matchById.phone;
            }
          }
        }

        if (pName.isEmpty || pName.toLowerCase() == 'patient') {
          final matchingPatient = _allPatients.firstWhere(
            (p) => p.name.isNotEmpty && p.name.toLowerCase() != 'patient',
            orElse: () => currentPatient.name.isNotEmpty ? currentPatient : PatientProfile(name: 'Patient'),
          );
          pName = matchingPatient.name.isNotEmpty ? matchingPatient.name : 'Patient';
          if (pPhone.isEmpty) pPhone = matchingPatient.phone;
        }

        final newReq = PatientConsultationRequest(
          id: prId,
          patientId: reqPatientId.isNotEmpty ? reqPatientId : pId,
          patientName: pName,
          patientPhone: pPhone,
          problemCategory: category,
          problemDescription: desc,
          symptoms: symptoms,
          preferredLocation: preferredLocation,
          severity: severity,
          submittedAt: pr['created_at'] != null ? DateTime.tryParse(pr['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
          status: normalizedStatus,
          adminNotes: adminNotes,
          assignedDoctorId: assignedDocId,
          assignedDoctorName: assignedDocName,
          assignedDoctorSpecialty: assignedDocSpecialty,
          assignedDoctorClinic: assignedDocClinic,
          confirmedTimeSlot: confirmedSlot,
          city: city,
          pincode: pincode,
          state: state,
        );

        final existingIdx = _requests.indexWhere((r) =>
            r.id == prId ||
            (r.id.isNotEmpty && prId.isNotEmpty && (r.id.contains(prId) || prId.contains(r.id))) ||
            (reqPatientId.isNotEmpty && r.patientId != null && r.patientId == reqPatientId && r.problemCategory.trim().toLowerCase() == category.trim().toLowerCase()) ||
            (pName.isNotEmpty && pName.toLowerCase() != 'patient' && r.patientName.trim().toLowerCase() == pName.trim().toLowerCase() && r.problemCategory.trim().toLowerCase() == category.trim().toLowerCase()) ||
            (r.id.startsWith('PR-') &&
                r.patientName.trim().toLowerCase() == pName.trim().toLowerCase() &&
                r.problemCategory.trim().toLowerCase() == category.trim().toLowerCase()));

        if (existingIdx != -1) {
          final existing = _requests[existingIdx];
          if (existing.status == 'Confirmed' || existing.status == 'Accepted') {
            if (normalizedStatus != 'Confirmed' && normalizedStatus != 'Accepted') {
              normalizedStatus = 'Confirmed';
            }
            if ((confirmedSlot == null || confirmedSlot.isEmpty) && existing.confirmedTimeSlot != null) {
              confirmedSlot = existing.confirmedTimeSlot;
            }
          }
          _requests[existingIdx] = PatientConsultationRequest(
            id: prId,
            patientId: reqPatientId.isNotEmpty ? reqPatientId : existing.patientId,
            patientName: pName,
            patientPhone: pPhone,
            problemCategory: category,
            problemDescription: desc,
            symptoms: symptoms,
            preferredLocation: preferredLocation,
            severity: severity,
            submittedAt: pr['created_at'] != null ? DateTime.tryParse(pr['created_at'].toString()) ?? DateTime.now() : existing.submittedAt,
            status: normalizedStatus,
            adminNotes: (adminNotes != null && adminNotes.isNotEmpty) ? adminNotes : existing.adminNotes,
            assignedDoctorId: (assignedDocId != null && assignedDocId.isNotEmpty) ? assignedDocId : existing.assignedDoctorId,
            assignedDoctorName: (assignedDocName.isNotEmpty && assignedDocName != 'null') ? assignedDocName : existing.assignedDoctorName,
            assignedDoctorSpecialty: (assignedDocSpecialty != null && assignedDocSpecialty.isNotEmpty) ? assignedDocSpecialty : existing.assignedDoctorSpecialty,
            assignedDoctorClinic: (assignedDocClinic != null && assignedDocClinic.isNotEmpty) ? assignedDocClinic : existing.assignedDoctorClinic,
            confirmedTimeSlot: (confirmedSlot != null && confirmedSlot.isNotEmpty) ? confirmedSlot : existing.confirmedTimeSlot,
            city: city.isNotEmpty ? city : existing.city,
            pincode: pincode.isNotEmpty ? pincode : existing.pincode,
            state: state.isNotEmpty ? state : existing.state,
          );
        } else {
          _requests.add(newReq);
        }
      }

      // Final deduplication pass to ensure 0 duplicate cards exist in memory
      final Map<String, PatientConsultationRequest> deduplicated = {};
      for (final r in _requests) {
        final pKey = (r.patientId != null && r.patientId!.isNotEmpty && !r.patientId!.startsWith('USR-'))
            ? r.patientId!.trim().toLowerCase()
            : (r.patientName.isNotEmpty && r.patientName.toLowerCase() != 'patient' && r.patientName != 'Patient Consultation' ? r.patientName.trim().toLowerCase() : '');
        final catKey = r.problemCategory.trim().toLowerCase();
        final key = (pKey.isNotEmpty && catKey.isNotEmpty) ? '${pKey}_$catKey' : r.id;

        if (!deduplicated.containsKey(key)) {
          deduplicated[key] = r;
        } else {
          final existing = deduplicated[key]!;
          final hasRealUuid = r.id.isNotEmpty && !r.id.startsWith('PR-') && !r.id.startsWith('REQ-');
          final hasAssignedDoctor = (r.assignedDoctorName != null && r.assignedDoctorName!.isNotEmpty && r.assignedDoctorName != 'null');
          final isConfirmed = (r.status == 'Confirmed' || r.status == 'Accepted' || r.status == 'Doctor Assigned');

          deduplicated[key] = PatientConsultationRequest(
            id: hasRealUuid ? r.id : existing.id,
            patientId: (r.patientId != null && r.patientId!.isNotEmpty) ? r.patientId : existing.patientId,
            patientName: (r.patientName.isNotEmpty && r.patientName != 'Patient' && r.patientName != 'Patient Consultation') ? r.patientName : existing.patientName,
            patientPhone: r.patientPhone.isNotEmpty ? r.patientPhone : existing.patientPhone,
            problemCategory: r.problemCategory.isNotEmpty ? r.problemCategory : existing.problemCategory,
            problemDescription: (r.problemDescription.isNotEmpty && r.problemDescription != 'Scheduled dental consultation') ? r.problemDescription : existing.problemDescription,
            symptoms: r.symptoms.isNotEmpty ? r.symptoms : existing.symptoms,
            preferredLocation: (r.preferredLocation != null && r.preferredLocation!.isNotEmpty) ? r.preferredLocation : existing.preferredLocation,
            severity: r.severity.isNotEmpty ? r.severity : existing.severity,
            submittedAt: r.submittedAt,
            status: (isConfirmed || r.status.isNotEmpty) ? r.status : existing.status,
            adminNotes: (r.adminNotes != null && r.adminNotes!.isNotEmpty) ? r.adminNotes : existing.adminNotes,
            assignedDoctorId: (r.assignedDoctorId != null && r.assignedDoctorId!.isNotEmpty) ? r.assignedDoctorId : existing.assignedDoctorId,
            assignedDoctorName: hasAssignedDoctor ? r.assignedDoctorName : existing.assignedDoctorName,
            assignedDoctorSpecialty: (r.assignedDoctorSpecialty != null && r.assignedDoctorSpecialty!.isNotEmpty) ? r.assignedDoctorSpecialty : existing.assignedDoctorSpecialty,
            assignedDoctorClinic: (r.assignedDoctorClinic != null && r.assignedDoctorClinic!.isNotEmpty) ? r.assignedDoctorClinic : existing.assignedDoctorClinic,
            confirmedTimeSlot: (r.confirmedTimeSlot != null && r.confirmedTimeSlot!.isNotEmpty) ? r.confirmedTimeSlot : existing.confirmedTimeSlot,
            city: r.city.isNotEmpty ? r.city : existing.city,
            pincode: r.pincode.isNotEmpty ? r.pincode : existing.pincode,
            state: r.state.isNotEmpty ? r.state : existing.state,
          );
        }
      }
      _requests.clear();
      _requests.addAll(deduplicated.values);

      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync problem requests error: $e');
    }
  }

  Future<void> syncDentistAssignedRequestsFromApi([String? dentistId]) async {
    try {
      String targetDocId = '';
      if (dentistId != null && dentistId.trim().isNotEmpty) {
        targetDocId = dentistId.trim();
      } else if (currentDoctor != null) {
        targetDocId = currentDoctor!.id.isNotEmpty
            ? currentDoctor!.id
            : (currentDoctor!.userId.isNotEmpty ? currentDoctor!.userId : currentDoctor!.email);
      } else if (Supabase.instance.client.auth.currentUser?.id != null) {
        targetDocId = Supabase.instance.client.auth.currentUser!.id;
      } else if (_allDoctors.isNotEmpty) {
        targetDocId = _allDoctors.first.id;
      }
      
      final List problemReqs = await ApiService().fetchDentistAssignedRequests(
        dentistId: targetDocId,
        dentistName: currentDoctor?.name,
      );

      final List<PatientConsultationRequest> freshAssigned = [];

      for (final pr in problemReqs) {
        final prId = (pr['_id'] ?? pr['id'] ?? '').toString();
        if (prId.isEmpty) continue;
        final reqPatientId = (pr['patient_id'] ?? pr['patientId'] ?? pr['patient']?['id'])?.toString() ?? '';
        final category = (pr['problem_category'] ?? pr['problemCategory'] ?? 'Dental Issue').toString();
        final desc = (pr['problem_description'] ?? pr['problemDescription'] ?? '').toString();
        final rawStatus = (pr['status'] ?? 'SUBMITTED').toString();
        final severity = (pr['severity'] ?? 'Moderate').toString();
        final adminNotes = pr['admin_notes']?.toString() ?? pr['adminNotes']?.toString();
        String? confirmedSlot = pr['confirmed_time_slot']?.toString() ?? pr['confirmedTimeSlot']?.toString();
        final symptoms = (pr['symptoms'] ?? '').toString();
        final preferredLocation = (pr['preferred_location'] ?? pr['preferredLocation'] ?? '').toString();
        final city = (pr['city'] ?? pr['patient']?['city'] ?? '').toString();
        final pincode = (pr['pincode'] ?? pr['patient']?['pincode'] ?? '').toString();
        final state = (pr['state'] ?? pr['patient']?['state'] ?? '').toString();

        final assignedDocId = (pr['assigned_doctor_id'] ?? pr['suggested_dentist_id'] ?? pr['dentist']?['id'])?.toString();
        String? assignedDocName = (pr['assigned_doctor_name'] ?? pr['assignedDoctorName'] ?? pr['dentist']?['name'])?.toString();
        String? assignedDocSpecialty = (pr['assigned_doctor_specialty'] ?? pr['assignedDoctorSpecialty'] ?? pr['dentist']?['specialty'])?.toString();
        String? assignedDocClinic = (pr['assigned_doctor_clinic'] ?? pr['assignedDoctorClinic'] ?? pr['dentist']?['clinicName'])?.toString();

        if ((assignedDocName == null || assignedDocName.isEmpty || assignedDocName == 'null') && assignedDocId != null && assignedDocId.isNotEmpty) {
          final matchedDoc = _allDoctors.firstWhere(
            (d) => d.id == assignedDocId || (d.userId.isNotEmpty && d.userId == assignedDocId) || d.email == assignedDocId || (d.name.isNotEmpty && assignedDocId.contains(d.name.replaceAll('Dr. ', '').trim())),
            orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
          );
          if (matchedDoc.name.isNotEmpty) {
            assignedDocName = matchedDoc.name;
            assignedDocSpecialty = matchedDoc.specialty;
            assignedDocClinic = matchedDoc.clinicName;
          }
        }

        if (assignedDocName == null || assignedDocName == 'null') {
          assignedDocName = '';
        }

        final rawStatusUpper = rawStatus.toUpperCase();
        String normalizedStatus;
        if (rawStatusUpper == 'CONFIRMED' ||
            rawStatusUpper == 'ACCEPTED' ||
            rawStatusUpper == 'DENTIST_ACCEPTED') {
          normalizedStatus = 'Confirmed';
        } else if (rawStatusUpper == 'DENTIST_ASSIGNED' ||
            rawStatusUpper == 'DENTIST_SUGGESTED' ||
            rawStatusUpper == 'PENDING_DENTIST_CONFIRMATION' ||
            (assignedDocName != null && assignedDocName.isNotEmpty)) {
          normalizedStatus = 'Doctor Assigned';
        } else if (rawStatusUpper == 'ADMIN_REVIEWED' || rawStatusUpper == 'ADMIN_REVIEW') {
          normalizedStatus = 'Admin Review';
        } else {
          normalizedStatus = 'Submitted';
        }

        // Preserve local confirmed state if already accepted in either collection
        final existingInRequests = _requests.where((r) => r.id == prId || (r.id.isNotEmpty && prId.isNotEmpty && (r.id.contains(prId) || prId.contains(r.id)))).toList();
        final existingInAssigned = _dentistAssignedRequests.where((r) => r.id == prId || (r.id.isNotEmpty && prId.isNotEmpty && (r.id.contains(prId) || prId.contains(r.id)))).toList();
        final isConfirmedLocal = (existingInRequests.isNotEmpty && (existingInRequests.first.status == 'Confirmed' || existingInRequests.first.status == 'Accepted')) ||
            (existingInAssigned.isNotEmpty && (existingInAssigned.first.status == 'Confirmed' || existingInAssigned.first.status == 'Accepted'));

        if (isConfirmedLocal) {
          normalizedStatus = 'Confirmed';
          if (confirmedSlot == null || confirmedSlot.isEmpty) {
            confirmedSlot = (existingInRequests.isNotEmpty && existingInRequests.first.confirmedTimeSlot != null && existingInRequests.first.confirmedTimeSlot!.isNotEmpty)
                ? existingInRequests.first.confirmedTimeSlot
                : (existingInAssigned.isNotEmpty ? existingInAssigned.first.confirmedTimeSlot : null);
          }
        }

        final patientObj = pr['patient'] ?? {};
        String pName = (pr['patientName'] ?? pr['patient_name'] ?? patientObj['name'] ?? '').toString().trim();
        String pPhone = (pr['patientPhone'] ?? pr['patient_phone'] ?? patientObj['phone'] ?? '').toString().trim();

        if (pName.isEmpty || pName.toLowerCase() == 'patient') {
          final matchingPatient = _allPatients.firstWhere(
            (p) => p.name.isNotEmpty && p.name.toLowerCase() != 'patient',
            orElse: () => currentPatient.name.isNotEmpty ? currentPatient : PatientProfile(name: 'Patient'),
          );
          pName = matchingPatient.name.isNotEmpty ? matchingPatient.name : 'Patient';
          if (pPhone.isEmpty) pPhone = matchingPatient.phone;
        }

        freshAssigned.add(
          PatientConsultationRequest(
            id: prId,
            patientId: reqPatientId.isNotEmpty ? reqPatientId : null,
            patientName: pName,
            patientPhone: pPhone,
            problemCategory: category,
            problemDescription: desc,
            symptoms: symptoms,
            preferredLocation: preferredLocation,
            severity: severity,
            submittedAt: pr['created_at'] != null ? DateTime.tryParse(pr['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
            status: normalizedStatus,
            adminNotes: adminNotes,
            assignedDoctorId: assignedDocId,
            assignedDoctorName: assignedDocName,
            assignedDoctorSpecialty: assignedDocSpecialty,
            assignedDoctorClinic: assignedDocClinic,
            confirmedTimeSlot: confirmedSlot,
            city: city,
            pincode: pincode,
            state: state,
          ),
        );
      }

      // Also merge any requests in _requests that match this doctor
      final currentDocName = (currentDoctor?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      final myDoctorIds = <String>{
        if (targetDocId.isNotEmpty) targetDocId,
        if (currentDoctor != null && currentDoctor!.id.isNotEmpty) currentDoctor!.id,
        if (currentDoctor != null && currentDoctor!.userId.isNotEmpty) currentDoctor!.userId,
        if (currentDoctor != null && currentDoctor!.email.isNotEmpty) currentDoctor!.email.toLowerCase(),
      };
      for (final doc in _allDoctors) {
        if (myDoctorIds.contains(doc.id) || (doc.userId.isNotEmpty && myDoctorIds.contains(doc.userId)) || (doc.email.isNotEmpty && myDoctorIds.contains(doc.email.toLowerCase()))) {
          if (doc.id.isNotEmpty) myDoctorIds.add(doc.id);
          if (doc.userId.isNotEmpty) myDoctorIds.add(doc.userId);
          if (doc.email.isNotEmpty) myDoctorIds.add(doc.email.toLowerCase());
        }
      }

      for (final req in _requests) {
        final aId = req.assignedDoctorId?.trim();
        final aName = req.assignedDoctorName?.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
        final isMatch = (aId != null && aId.isNotEmpty && myDoctorIds.contains(aId)) ||
            (currentDocName.isNotEmpty && currentDocName != 'dentist' && currentDocName != 'doctor' && aName != null && aName.isNotEmpty && (aName == currentDocName || currentDocName.contains(aName) || aName.contains(currentDocName)));
        if (isMatch && !freshAssigned.any((r) => r.id == req.id)) {
          freshAssigned.add(req);
        }
      }

      _dentistAssignedRequests.clear();
      _dentistAssignedRequests.addAll(freshAssigned);
      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync dentist assigned requests error: $e');
    }
  }

  Future<void> syncClinicsFromApi() async {
    try {
      final list = await ApiService().fetchClinics();
      _allClinics.clear();
      if (list.isNotEmpty) {
        for (final item in list) {
          _allClinics.add(ClinicModel.fromJson(item));
        }
      }
      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync clinics error: $e');
    }
  }

  Future<bool> registerClinic({
    required String clinicName,
    required String location,
    List<String>? services,
    List<Map<String, dynamic>>? pricing,
  }) async {
    final res = await ApiService().createClinicProfile(
      clinicName: clinicName,
      location: location,
      services: services,
      pricing: pricing,
    );

    if (res['success'] == true) {
      await syncClinicsFromApi();
      return true;
    }
    return false;
  }

  Future<void> syncDoctorsFromApi() async {
    try {
      final apiDentists = await ApiService().fetchDentists();
      if (apiDentists.isNotEmpty) {
        _allDoctors.clear();
        for (final dMap in apiDentists) {
          final id = dMap['id']?.toString() ?? dMap['_id']?.toString() ?? '';
          final userObj = dMap['users'] ?? dMap['user'] ?? {};
          final clinicObj = dMap['clinics'] ?? dMap['clinic'] ?? {};
          
          var rawName = (userObj['name'] ?? dMap['name'] ?? dMap['dentist_name'] ?? '').toString().trim();
          if (rawName.isEmpty || rawName.toLowerCase() == 'dentist' || rawName == 'Dr.') {
            final cNameStr = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString().trim();
            if (cNameStr.isNotEmpty) {
              rawName = cNameStr;
            } else {
              rawName = 'Specialist Dentist';
            }
          }
          final formattedName = rawName.startsWith('Dr.') ? rawName : 'Dr. $rawName';
          final email = (userObj['email'] ?? dMap['email'] ?? '').toString();
          final phone = (userObj['phone'] ?? dMap['phone'] ?? '+1 202 555 0100').toString();
          final specialty = (dMap['speciality'] ?? dMap['specialty'] ?? 'General Dentistry').toString();
          final licNum = (dMap['license_number'] ?? dMap['licenseNumber'] ?? 'DEN-LIC-REG').toString();
          final cName = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString();
          final cLoc = (clinicObj['location'] ?? dMap['location'] ?? '').toString();

          final doctorState = (dMap['state'] ?? userObj['state'] ?? '').toString();
          final doctorCity = (dMap['city'] ?? userObj['city'] ?? '').toString();
          final doctorPincode = (dMap['pincode'] ?? userObj['pincode'] ?? dMap['postal_code'] ?? '').toString();
          final lat = (dMap['latitude'] ?? userObj['latitude']) != null ? double.tryParse((dMap['latitude'] ?? userObj['latitude']).toString()) : null;
          final lng = (dMap['longitude'] ?? userObj['longitude']) != null ? double.tryParse((dMap['longitude'] ?? userObj['longitude']).toString()) : null;

          List<String> doctorLangs = ['English'];
          final rawLangs = dMap['languages'] ?? userObj['languages'];
          if (rawLangs != null) {
            if (rawLangs is List) {
              doctorLangs = rawLangs.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
            } else if (rawLangs is String && rawLangs.trim().isNotEmpty) {
              doctorLangs = rawLangs.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            }
          }
          if (doctorLangs.isEmpty) {
            if (userObj['device_token'] != null && userObj['device_token'].toString().startsWith('{')) {
              try {
                final meta = jsonDecode(userObj['device_token'].toString());
                if (meta['languages'] is List) {
                  doctorLangs = List<String>.from((meta['languages'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
                }
              } catch (_) {}
            }
          }
          if (doctorLangs.isEmpty) doctorLangs = ['English'];

          final doctorUserId = (dMap['user_id'] ?? userObj['id'] ?? '').toString();

          _allDoctors.add(DoctorModel(
            id: id.isNotEmpty ? id : 'DOC-${100 + _allDoctors.length + 1}',
            userId: doctorUserId,
            name: formattedName,
            specialty: specialty,
            qualification: dMap['qualifications'] ?? dMap['qualification'] ?? 'BDS, MDS',
            experienceYears: dMap['experience_years'] ?? dMap['experienceYears'] ?? 5,
            rating: (dMap['rating'] ?? 5.0).toDouble(),
            reviewCount: dMap['reviews_count'] ?? 1,
            clinicName: cName,
            clinicAddress: cLoc,
            phone: phone,
            email: email,
            status: dMap['availability_status'] ?? 'Available',
            nextAvailableSlots: ['Today, 2:00 PM', 'Tomorrow, 10:00 AM'],
            consultationFee: '\$75',
            licenseNumber: licNum,
            state: doctorState,
            city: doctorCity,
            pincode: doctorPincode,
            languages: doctorLangs,
            latitude: lat,
            longitude: lng,
          ));
        }
      }
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser != null && authUser.email != null && authUser.email!.isNotEmpty) {
        final authEmailLower = authUser.email!.toLowerCase();
        final authName = (authUser.userMetadata?['name'] ?? '').toString().toLowerCase();
        for (final d in _allDoctors) {
          if (d.email.toLowerCase() == authEmailLower ||
              (d.id.isNotEmpty && d.id == authUser.id) ||
              (d.userId.isNotEmpty && d.userId == authUser.id) ||
              (authName.isNotEmpty && d.name.toLowerCase().contains(authName))) {
            currentDoctor = d;
            break;
          }
        }
      }
      if (currentDoctor != null) {
        final match = _allDoctors.firstWhere(
          (d) => (currentDoctor!.id.isNotEmpty && d.id == currentDoctor!.id) ||
              (d.userId.isNotEmpty && d.userId == currentDoctor!.userId) ||
              (d.email.isNotEmpty && d.email.toLowerCase() == currentDoctor!.email.toLowerCase()) ||
              (d.name.isNotEmpty && d.name.toLowerCase() == currentDoctor!.name.toLowerCase()),
          orElse: () => currentDoctor!,
        );
        currentDoctor = match;
      }
      _saveToStorage();
      notifyListeners();
      if (_isDentistMode) {
        syncDentistAssignedRequestsFromApi();
      }
    } catch (e) {
      debugPrint('Sync doctors error: $e');
    }
  }

  /// Fetch doctors from API filtered by state, city, pincode, specialty, availability, language.
  /// Returns filtered list without modifying the global [_allDoctors] cache.
  Future<List<DoctorModel>> fetchDoctorsFiltered({String? state, String? city, String? pincode, String? specialty, String? availability, String? language}) async {
    try {
      final apiDentists = await ApiService().fetchDentists(state: state, city: city, pincode: pincode, specialty: specialty, availability: availability, language: language);
      final filtered = <DoctorModel>[];
      for (final dMap in apiDentists) {
        final id = dMap['id']?.toString() ?? dMap['_id']?.toString() ?? '';
        final userObj = dMap['users'] ?? dMap['user'] ?? {};
        final clinicObj = dMap['clinics'] ?? dMap['clinic'] ?? {};
        final name = (userObj['name'] ?? dMap['name'] ?? 'Dentist').toString();
        final email = (userObj['email'] ?? dMap['email'] ?? '').toString();
        final phone = (userObj['phone'] ?? dMap['phone'] ?? '').toString();
        final spec = (dMap['speciality'] ?? dMap['specialty'] ?? 'General Dentistry').toString();
        final licNum = (dMap['license_number'] ?? dMap['licenseNumber'] ?? 'DEN-LIC-REG').toString();
        final cName = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString();
        final cLoc = (clinicObj['location'] ?? dMap['location'] ?? '').toString();
        final doctorState = (dMap['state'] ?? userObj['state'] ?? '').toString();
        final doctorCity = (dMap['city'] ?? userObj['city'] ?? '').toString();
        final doctorPincode = (dMap['pincode'] ?? userObj['pincode'] ?? dMap['postal_code'] ?? '').toString();
        final lat = (dMap['latitude'] ?? userObj['latitude']) != null ? double.tryParse((dMap['latitude'] ?? userObj['latitude']).toString()) : null;
        final lng = (dMap['longitude'] ?? userObj['longitude']) != null ? double.tryParse((dMap['longitude'] ?? userObj['longitude']).toString()) : null;

        List<String> doctorLangs = ['English'];
        final rawLangs = dMap['languages'] ?? userObj['languages'];
        if (rawLangs != null) {
          if (rawLangs is List) {
            doctorLangs = rawLangs.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
          } else if (rawLangs is String && rawLangs.trim().isNotEmpty) {
            doctorLangs = rawLangs.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        }
        if (doctorLangs.isEmpty) {
          if (userObj['device_token'] != null && userObj['device_token'].toString().startsWith('{')) {
            try {
              final meta = jsonDecode(userObj['device_token'].toString());
              if (meta['languages'] is List) {
                doctorLangs = List<String>.from((meta['languages'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
              }
            } catch (_) {}
          }
        }
        if (doctorLangs.isEmpty) doctorLangs = ['English'];

        final formattedName = name.startsWith('Dr.') ? name : 'Dr. $name';

        filtered.add(DoctorModel(
          id: id.isNotEmpty ? id : 'DOC-${filtered.length + 1}',
          name: formattedName,
          specialty: spec,
          qualification: dMap['qualifications'] ?? dMap['qualification'] ?? 'BDS, MDS',
          experienceYears: dMap['experience_years'] ?? dMap['experienceYears'] ?? 5,
          rating: (dMap['rating'] ?? 5.0).toDouble(),
          reviewCount: dMap['reviews_count'] ?? 1,
          clinicName: cName,
          clinicAddress: cLoc,
          phone: phone,
          email: email,
          status: dMap['availability_status'] ?? 'Available',
          nextAvailableSlots: ['Today, 2:00 PM', 'Tomorrow, 10:00 AM'],
          consultationFee: '\$75',
          licenseNumber: licNum,
          state: doctorState,
          city: doctorCity,
          pincode: doctorPincode,
          languages: doctorLangs,
          latitude: lat,
          longitude: lng,
        ));
      }
      return filtered;
    } catch (e) {
      debugPrint('fetchDoctorsFiltered error: $e');
      return [];
    }
  }

  Future<void> syncAppointmentsFromApi() async {
    try {
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : null;
      final dId = currentDoctor?.id.isNotEmpty == true ? currentDoctor!.id : (currentDoctor?.userId.isNotEmpty == true ? currentDoctor!.userId : null);
      
      final list = _isDentistMode
          ? (dId != null ? await ApiService().fetchAppointments(dentistId: dId) : <dynamic>[])
          : (pId != null ? await ApiService().fetchAppointments(patientId: pId) : <dynamic>[]);
      
      if (list.isEmpty) {
        if (_isDentistMode) {
          _requests.removeWhere((r) => r.problemDescription == 'Scheduled dental consultation');
          _saveToStorage();
          notifyListeners();
        }
        return;
      }

      for (final item in list) {
        final itemPatientId = (item['patient_id'] ?? item['patientId'] ?? item['patient']?['id'])?.toString();
        final itemDentistId = (item['dentist_id'] ?? item['dentistId'])?.toString();
        final authUser = Supabase.instance.client.auth.currentUser;
        final isAdmin = (authUser?.email != null && (authUser!.email!.toLowerCase().contains('admin') || authUser.email!.toLowerCase() == 'anusripvc202@gmail.com')) ||
                        currentPatient.email.toLowerCase().contains('admin');

        if (_isDentistMode) {
          final myId = currentDoctor?.id ?? '';
          final myUserId = currentDoctor?.userId ?? '';
          if (itemDentistId != null && itemDentistId.isNotEmpty && itemDentistId != myId && itemDentistId != myUserId) {
            continue; // Skip appointments for other dentists!
          }
        }

        if (!isAdmin && !_isDentistMode && pId != null && pId.isNotEmpty && itemPatientId != null && itemPatientId.isNotEmpty && itemPatientId != pId && !itemPatientId.contains(pId)) {
          continue; // Skip appointments belonging to another patient!
        }

        final reqId = (item['_id'] ?? item['id'] ?? 'REQ-${item['patient_id']}-${DateTime.now().millisecondsSinceEpoch}').toString();
        
        final patientObj = item['patient'] ?? item['users'] ?? {};
        final String rawPName = (patientObj['name'] ?? item['patient_name'] ?? item['patientName'] ?? '').toString();
        final String pName = (rawPName.isNotEmpty && rawPName != 'Patient') 
            ? rawPName 
            : (currentPatient.name.isNotEmpty ? currentPatient.name : 'Patient Consultation');

        final String pPhone = (patientObj['phone'] ?? item['phone'] ?? (currentPatient.phone.isNotEmpty ? currentPatient.phone : '')).toString();

        final rawD = (item['dentist_name'] ?? item['dentistName'] ?? item['dentist_id'] ?? '').toString();
        String? assignedDocName;
        if (rawD.isNotEmpty && !rawD.contains('-')) {
          assignedDocName = rawD;
        } else if (rawD.isNotEmpty) {
          final matchedDoc = _allDoctors.firstWhere((d) => d.id == rawD || d.userId == rawD, orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''));
          if (matchedDoc.name.isNotEmpty) {
            assignedDocName = matchedDoc.name;
          }
        }

        final clinicObj = item['clinic'] ?? {};
        final clinic = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? item['clinic_name'] ?? item['clinicName'] ?? '').toString();
        final treatment = item['treatment'] ?? 'Dental Consultation';
        final slot = item['time_slot'] ?? item['timeSlot'];
        final statusStr = (item['status'] ?? 'CONFIRMED').toString();

        final existingIndex = _requests.indexWhere((r) =>
            r.id == reqId ||
            (itemPatientId != null && itemPatientId.isNotEmpty && r.patientId != null && r.patientId == itemPatientId && r.problemCategory.trim().toLowerCase() == treatment.toString().trim().toLowerCase()) ||
            (pName.isNotEmpty && pName.toLowerCase() != 'patient' && r.patientName.trim().toLowerCase() == pName.trim().toLowerCase() && r.problemCategory.trim().toLowerCase() == treatment.toString().trim().toLowerCase()) ||
            (r.patientName == pName && r.assignedDoctorName != null && r.confirmedTimeSlot == slot?.toString()));

        if (existingIndex != -1) {
          if (pName != 'Patient Consultation' && pName != 'Patient') {
            _requests[existingIndex].patientName = pName;
          }
          if (pPhone.isNotEmpty) {
            _requests[existingIndex].patientPhone = pPhone;
          }
          if (slot != null && slot.toString().isNotEmpty && slot.toString() != 'Pending Review') {
            _requests[existingIndex].confirmedTimeSlot = slot.toString();
          }
          if (assignedDocName != null && assignedDocName.isNotEmpty && assignedDocName != 'null') {
            _requests[existingIndex].assignedDoctorName = assignedDocName;
          }
          if (itemDentistId != null && itemDentistId.isNotEmpty) {
            _requests[existingIndex].assignedDoctorId = itemDentistId;
          }
          _requests[existingIndex].status = statusStr;
          if (clinic.isNotEmpty) {
            _requests[existingIndex].assignedDoctorClinic = clinic;
          }
        } else {
          _requests.add(
            PatientConsultationRequest(
              id: reqId,
              patientId: itemPatientId,
              patientName: pName,
              patientPhone: pPhone,
              problemCategory: treatment.toString(),
              problemDescription: 'Scheduled dental consultation',
              severity: 'Moderate',
              submittedAt: item['created_at'] != null ? DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
              status: statusStr,
              assignedDoctorId: itemDentistId ?? dId,
              assignedDoctorName: assignedDocName,
              assignedDoctorSpecialty: 'Dental Specialist',
              assignedDoctorClinic: clinic.isNotEmpty ? clinic : null,
              confirmedTimeSlot: slot?.toString(),
              adminNotes: 'Consultation record',
              whatsappNotificationSent: true,
            ),
          );
        }
      }

      // Final deduplication pass to ensure 0 duplicate cards exist in memory
      final Map<String, PatientConsultationRequest> deduplicated = {};
      for (final r in _requests) {
        final pKey = (r.patientId != null && r.patientId!.isNotEmpty && !r.patientId!.startsWith('USR-'))
            ? r.patientId!.trim().toLowerCase()
            : (r.patientName.isNotEmpty && r.patientName.toLowerCase() != 'patient' && r.patientName != 'Patient Consultation' ? r.patientName.trim().toLowerCase() : '');
        final catKey = r.problemCategory.trim().toLowerCase();
        final key = (pKey.isNotEmpty && catKey.isNotEmpty) ? '${pKey}_$catKey' : r.id;

        if (!deduplicated.containsKey(key)) {
          deduplicated[key] = r;
        } else {
          final existing = deduplicated[key]!;
          final hasRealUuid = r.id.isNotEmpty && !r.id.startsWith('PR-') && !r.id.startsWith('REQ-');
          final hasAssignedDoctor = (r.assignedDoctorName != null && r.assignedDoctorName!.isNotEmpty && r.assignedDoctorName != 'null');
          final isConfirmed = (r.status == 'Confirmed' || r.status == 'Accepted' || r.status == 'Doctor Assigned');

          deduplicated[key] = PatientConsultationRequest(
            id: hasRealUuid ? r.id : existing.id,
            patientId: (r.patientId != null && r.patientId!.isNotEmpty) ? r.patientId : existing.patientId,
            patientName: (r.patientName.isNotEmpty && r.patientName != 'Patient' && r.patientName != 'Patient Consultation') ? r.patientName : existing.patientName,
            patientPhone: r.patientPhone.isNotEmpty ? r.patientPhone : existing.patientPhone,
            problemCategory: r.problemCategory.isNotEmpty ? r.problemCategory : existing.problemCategory,
            problemDescription: (r.problemDescription.isNotEmpty && r.problemDescription != 'Scheduled dental consultation') ? r.problemDescription : existing.problemDescription,
            symptoms: r.symptoms.isNotEmpty ? r.symptoms : existing.symptoms,
            preferredLocation: (r.preferredLocation != null && r.preferredLocation!.isNotEmpty) ? r.preferredLocation : existing.preferredLocation,
            severity: r.severity.isNotEmpty ? r.severity : existing.severity,
            submittedAt: r.submittedAt,
            status: (isConfirmed || r.status.isNotEmpty) ? r.status : existing.status,
            adminNotes: (r.adminNotes != null && r.adminNotes!.isNotEmpty) ? r.adminNotes : existing.adminNotes,
            assignedDoctorId: (r.assignedDoctorId != null && r.assignedDoctorId!.isNotEmpty) ? r.assignedDoctorId : existing.assignedDoctorId,
            assignedDoctorName: hasAssignedDoctor ? r.assignedDoctorName : existing.assignedDoctorName,
            assignedDoctorSpecialty: (r.assignedDoctorSpecialty != null && r.assignedDoctorSpecialty!.isNotEmpty) ? r.assignedDoctorSpecialty : existing.assignedDoctorSpecialty,
            assignedDoctorClinic: (r.assignedDoctorClinic != null && r.assignedDoctorClinic!.isNotEmpty) ? r.assignedDoctorClinic : existing.assignedDoctorClinic,
            confirmedTimeSlot: (r.confirmedTimeSlot != null && r.confirmedTimeSlot!.isNotEmpty) ? r.confirmedTimeSlot : existing.confirmedTimeSlot,
            city: r.city.isNotEmpty ? r.city : existing.city,
            pincode: r.pincode.isNotEmpty ? r.pincode : existing.pincode,
            state: r.state.isNotEmpty ? r.state : existing.state,
          );
        }
      }
      _requests.clear();
      _requests.addAll(deduplicated.values);

      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync appointments error: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dentaguru_patient_profile', jsonEncode(currentPatient.toJson()));
      if (currentPatient.email.isNotEmpty) {
        await prefs.setString('dentaguru_patient_profile_${currentPatient.email.trim().toLowerCase()}', jsonEncode(currentPatient.toJson()));
      }
      if (currentDoctor != null) {
        await prefs.setString('dentaguru_current_doctor', jsonEncode(currentDoctor!.toJson()));
        if (currentDoctor!.email.isNotEmpty) {
          await prefs.setString('dentaguru_current_doctor_${currentDoctor!.email.trim().toLowerCase()}', jsonEncode(currentDoctor!.toJson()));
        }
      }
      await prefs.setString('dentaguru_requests', jsonEncode(_requests.map((r) => r.toJson()).toList()));
      await prefs.setString('dentaguru_dentist_assigned_requests', jsonEncode(_dentistAssignedRequests.map((r) => r.toJson()).toList()));
      await prefs.setString('dentaguru_all_doctors', jsonEncode(_allDoctors.map((d) => d.toJson()).toList()));
      await prefs.setString('dentaguru_all_patients', jsonEncode(_allPatients.map((p) => p.toJson()).toList()));
      await prefs.setString('dentaguru_medical_records', jsonEncode(_medicalRecords));
      if (_isSubAdminMode) {
        await prefs.setString('dentaguru_sub_admin_session', jsonEncode({
          'isSubAdminMode': _isSubAdminMode,
          'id': _subAdminId,
          'name': _subAdminName,
          'email': _subAdminEmail,
          'phone': _subAdminPhone,
          'status': _subAdminStatus,
          'permissions': _subAdminPermissions.toList(),
        }));
      } else {
        await prefs.remove('dentaguru_sub_admin_session');
      }
    } catch (e) {
      debugPrint('Error saving PatientProblemService state to storage: $e');
    }
  }

  Future<void> clearDoctorSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dentaguru_current_doctor');
      if (currentDoctor != null && currentDoctor!.email.isNotEmpty) {
        await prefs.remove('dentaguru_current_doctor_${currentDoctor!.email.trim().toLowerCase()}');
      }
      currentDoctor = null;
      _dentistAssignedRequests.clear();
      _isDentistMode = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing doctor session: $e');
    }
  }

  Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      currentPatient = PatientProfile();
      currentDoctor = null;
      _allDoctors.clear();
      _allPatients.clear();
      _allClinics.clear();
      _requests.clear();
      _medicalRecords.clear();
      _appNotifications.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing all local data: $e');
    }
  }

  void updatePatientProfile({
    String id = '',
    required String name,
    required String email,
    required String phone,
    required String age,
    required String gender,
    required String bloodGroup,
    required String emergencyContact,
    String address = '',
    String city = '',
    String pincode = '',
    Uint8List? photoBytes,
  }) {
    if (photoBytes != null) {
      _userPhotoCache[email.trim().toLowerCase()] = photoBytes;
    }
    final cachedPhoto = photoBytes ?? _userPhotoCache[email.trim().toLowerCase()];

    currentPatient = PatientProfile(
      id: id.trim(),
      name: name.trim().isEmpty ? 'Patient' : name.trim(),
      email: email.trim().isEmpty ? 'patient@dentaguru.com' : email.trim(),
      phone: phone.trim(),
      age: age.trim(),
      gender: gender.isEmpty ? 'Female' : gender,
      bloodGroup: bloodGroup.isEmpty ? 'O Positive (O+)' : bloodGroup,
      emergencyContact: emergencyContact.trim().isEmpty ? phone.trim() : emergencyContact.trim(),
      address: address.trim(),
      city: city.trim(),
      pincode: pincode.trim(),
      photoBytes: cachedPhoto,
    );
    _saveToStorage();

    // Persist profile metadata to Supabase DB users table in device_token column
    if (email.trim().isNotEmpty) {
      try {
        final profileMeta = jsonEncode({
          'age': age.trim(),
          'bloodGroup': bloodGroup.trim(),
          'gender': gender.trim(),
          'emergencyContact': emergencyContact.trim(),
          'city': city.trim(),
          'pincode': pincode.trim(),
          'address': address.trim(),
        });
        Supabase.instance.client.from('users').update({
          'device_token': profileMeta,
        }).ilike('email', email.trim()).then((_) {}).catchError((_) {});
      } catch (_) {}
    }

    syncAllDataFromApi();
    notifyListeners();
  }

  Future<void> submitProblem({
    required String problemCategory,
    required String problemDescription,
    required String severity,
    String symptoms = '',
    String preferredLocation = '',
    List<String> attachments = const [],
  }) async {
    String pName = currentPatient.name.trim();
    if (pName.isEmpty || pName.toLowerCase() == 'patient') {
      pName = currentPatient.name.isNotEmpty ? currentPatient.name : 'Patient';
    }
    String pPhone = currentPatient.phone.trim();
    String pCity = currentPatient.city.trim();
    String pPincode = currentPatient.pincode.trim();
    String pState = currentPatient.state.trim();

    if (pCity.isEmpty && _allPatients.isNotEmpty) {
      final match = _allPatients.firstWhere(
        (p) => (p.email.isNotEmpty && p.email.toLowerCase() == currentPatient.email.toLowerCase()) && p.city.isNotEmpty,
        orElse: () => PatientProfile(),
      );
      if (match.city.isNotEmpty) {
        pCity = match.city;
        if (pPincode.isEmpty) pPincode = match.pincode;
        if (pState.isEmpty) pState = match.state;
      }
    }

    // Insert a temp record immediately for optimistic UI feedback
    final tempId = 'PR-${DateTime.now().millisecondsSinceEpoch}';
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : Supabase.instance.client.auth.currentUser?.id;
    final newReq = PatientConsultationRequest(
      id: tempId,
      patientId: pId,
      patientName: pName,
      patientPhone: pPhone,
      problemCategory: problemCategory,
      problemDescription: problemDescription,
      symptoms: symptoms,
      preferredLocation: preferredLocation,
      attachments: attachments,
      severity: severity,
      submittedAt: DateTime.now(),
      status: 'SUBMITTED',
      city: pCity,
      pincode: pPincode,
      state: pState,
    );
    _requests.insert(0, newReq);
    _saveToStorage();
    notifyListeners();

    // 🌐 Save immediately to Supabase PostgreSQL database table ('patient_problem_requests')
    // then re-sync so the local record gets the real UUID from the DB
    try {
      await ApiService().createProblemRequest(
        problemCategory: problemCategory,
        problemDescription: problemDescription,
        symptoms: symptoms,
        preferredLocation: preferredLocation,
        attachments: attachments,
        patientName: pName,
        patientPhone: pPhone,
        city: pCity,
        pincode: pPincode,
        state: pState,
      );
      // Replace temp record with the server-assigned UUID record
      await syncProblemRequestsFromApi();
    } catch (e) {
      debugPrint('Error saving problem request to Supabase DB: $e');
    }
  }

  Future<void> markAdminReviewed(String requestId, {String? notes}) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      final req = _requests[index];
      if (req.status == 'Submitted' || req.status == 'PENDING_ADMIN_REVIEW' || req.status == 'SUBMITTED') {
        req.status = 'Admin Review';
        if (notes != null && notes.isNotEmpty) req.adminNotes = notes;
        _saveToStorage();
        notifyListeners();

        try {
          await ApiService().markAdminReviewed(requestId, notes: notes);
        } catch (e) {
          debugPrint('Error syncing markAdminReviewed to API: $e');
        }

        try {
          await Supabase.instance.client.from('patient_problem_requests').update({
            'status': 'ADMIN_REVIEWED',
            if (notes != null && notes.isNotEmpty) 'admin_notes': notes,
          }).eq('id', requestId);
        } catch (e) {
          debugPrint('Supabase direct markAdminReviewed update error: $e');
        }
      }
    }
  }


  Future<void> assignDoctorToRequest({
    required String requestId,
    required DoctorModel doctor,
    required String adminNotes,
  }) async {
    // Resolve valid dentist table UUID to satisfy foreign key constraints
    String targetDentistTableId = doctor.id;
    try {
      final dRes = await Supabase.instance.client
          .from('dentists')
          .select('id')
          .or('id.eq.${doctor.id},user_id.eq.${doctor.id}')
          .maybeSingle();
      if (dRes != null && dRes['id'] != null) {
        targetDentistTableId = dRes['id'].toString();
      }
    } catch (_) {}

    for (final req in _requests) {
      if (req.id == requestId || req.id.contains(requestId) || requestId.contains(req.id)) {
        req.status = 'Doctor Assigned';
        req.assignedDoctorId = targetDentistTableId;
        req.assignedDoctorName = doctor.name;
        req.assignedDoctorSpecialty = doctor.specialty;
        req.assignedDoctorClinic = doctor.clinicName;
        req.adminNotes = adminNotes;
        req.whatsappNotificationSent = true;
      }
    }
    _saveToStorage();
    notifyListeners();

    // 🌐 Save immediately to Backend API & Supabase PostgreSQL Database
    try {
      await ApiService().suggestDentist(
        requestId: requestId,
        dentistId: targetDentistTableId,
        notes: adminNotes,
        doctorName: doctor.name,
        doctorSpecialty: doctor.specialty,
        doctorClinic: doctor.clinicName,
      );
    } catch (e) {
      debugPrint('Error syncing assignDoctorToRequest to API: $e');
    }

    try {
      // 1. Update native columns in Supabase patient_problem_requests
      await Supabase.instance.client.from('patient_problem_requests').update({
        'status': 'DENTIST_ASSIGNED',
        'suggested_dentist_id': targetDentistTableId,
        'admin_notes': adminNotes,
      }).eq('id', requestId);
    } catch (e) {
      debugPrint('Supabase direct doctor assignment update notice: $e');
    }

    try {
      // 2. Insert record into Supabase dentist_suggestions table
      await Supabase.instance.client.from('dentist_suggestions').insert({
        'request_id': requestId,
        'dentist_id': targetDentistTableId,
        'status': 'SUGGESTED',
        'notes': adminNotes,
      });
    } catch (e) {
      debugPrint('Supabase dentist_suggestions insert notice: $e');
    }

    await syncProblemRequestsFromApi();
    notifyListeners();
  }

  /// Retrieves the latest dental consultation / problem request for a given patient
  PatientConsultationRequest? getLatestRequestForPatient(PatientProfile patient) {
    final matchingRequests = _requests.where((r) {
      if (patient.id.isNotEmpty && r.patientId != null && r.patientId == patient.id) return true;
      if (patient.phone.isNotEmpty && r.patientPhone.isNotEmpty && r.patientPhone.trim() == patient.phone.trim()) return true;
      if (patient.name.isNotEmpty && r.patientName.isNotEmpty && r.patientName.trim().toLowerCase() == patient.name.trim().toLowerCase()) return true;
      if (patient.email.isNotEmpty && r.patientPhone.isNotEmpty && r.patientPhone.toLowerCase() == patient.email.toLowerCase()) return true;
      return false;
    }).toList();

    if (matchingRequests.isEmpty) return null;

    matchingRequests.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return matchingRequests.first;
  }

  /// Retrieves the currently assigned dentist for a patient
  DoctorModel? getAssignedDoctorForPatient(PatientProfile patient) {
    final req = getLatestRequestForPatient(patient);
    if (req == null) return null;

    final docId = req.assignedDoctorId;
    final docName = req.assignedDoctorName;

    if ((docId == null || docId.trim().isEmpty || docId == 'null') &&
        (docName == null || docName.trim().isEmpty || docName == 'null')) {
      return null;
    }

    // Lookup in _allDoctors
    for (final doc in _allDoctors) {
      if (docId != null && docId.isNotEmpty) {
        if (doc.id == docId || doc.userId == docId) return doc;
      }
      if (docName != null && docName.isNotEmpty) {
        if (doc.name.trim().toLowerCase() == docName.trim().toLowerCase()) return doc;
      }
    }

    // If assigned doctor has basic info stored in request model, build DoctorModel
    if (docName != null && docName.trim().isNotEmpty && docName != 'null') {
      return DoctorModel(
        id: docId ?? 'doc_${DateTime.now().millisecondsSinceEpoch}',
        name: docName,
        specialty: req.assignedDoctorSpecialty ?? 'General Dentistry',
        qualification: 'BDS, MDS',
        experienceYears: 5,
        rating: 5.0,
        reviewCount: 0,
        clinicName: req.assignedDoctorClinic ?? 'DentaGuru Care Center',
        phone: '',
        email: '',
        status: 'Available',
        nextAvailableSlots: ['10:00 AM', '02:00 PM', '04:30 PM'],
        consultationFee: '₹500',
        city: req.city.isNotEmpty ? req.city : 'Hyderabad',
        state: req.state,
        pincode: req.pincode,
        languages: const ['English', 'Telugu', 'Hindi'],
      );
    }

    return null;
  }

  Future<void> acceptReferralByDentist(String requestId, {String? timeSlot, String? date}) async {
    final slotText = (timeSlot != null && timeSlot.trim().isNotEmpty) ? timeSlot.trim() : 'Today, 2:30 PM';

    debugPrint('[ACCEPT] API request started');
    debugPrint('[ACCEPT] Referral ID: $requestId');

    final index = _requests.indexWhere((r) => r.id == requestId || r.id.contains(requestId) || requestId.contains(r.id));
    if (index != -1) {
      final req = _requests[index];
      debugPrint('[ACCEPT] Patient ID: ${req.patientId}');
      debugPrint('[ACCEPT] Dentist ID: ${req.assignedDoctorId ?? ""}');
      req.status = 'Confirmed';
      req.confirmedTimeSlot = slotText;
      if (date != null && date.trim().isNotEmpty) req.confirmedDate = date.trim();
    }

    final assignedIndex = _dentistAssignedRequests.indexWhere((r) => r.id == requestId || r.id.contains(requestId) || requestId.contains(r.id));
    if (assignedIndex != -1) {
      final req = _dentistAssignedRequests[assignedIndex];
      req.status = 'Confirmed';
      req.confirmedTimeSlot = slotText;
      if (date != null && date.trim().isNotEmpty) req.confirmedDate = date.trim();
    }

    if (index == -1 && assignedIndex != -1) {
      _requests.add(_dentistAssignedRequests[assignedIndex]);
    }

    final reqObj = index != -1 ? _requests[index] : (assignedIndex != -1 ? _dentistAssignedRequests[assignedIndex] : null);
    final reqName = reqObj?.patientName ?? 'Patient';
    final docName = reqObj?.assignedDoctorName ?? 'Your Doctor';
    final category = reqObj?.problemCategory ?? 'Dental Issue';

    addNotification(
      recipientRole: 'Patient',
      recipientId: reqName,
      title: '🎉 Consultation Accepted!',
      message: '${docName} accepted your consultation for $category. Confirmed Time Slot: $slotText',
    );

    addNotification(
      recipientRole: 'Admin',
      recipientId: 'ALL_ADMINS',
      title: '✅ Doctor Accepted Referral',
      message: '${docName} accepted consultation for $reqName. Time Slot: $slotText',
    );

    _saveToStorage();
    notifyListeners();

    // 1. Direct Supabase PostgreSQL update
    try {
      await Supabase.instance.client.from('patient_problem_requests').update({
        'status': 'DENTIST_ACCEPTED',
      }).eq('id', requestId);
    } catch (e) {
      debugPrint('Supabase accept status update error: $e');
    }

    try {
      await Supabase.instance.client.from('patient_problem_requests').update({
        'confirmed_time_slot': slotText,
        if (date != null && date.trim().isNotEmpty) 'confirmed_date': date.trim(),
      }).eq('id', requestId);
    } catch (_) {}

    try {
      await Supabase.instance.client.from('dentist_suggestions').update({
        'status': 'ACCEPTED',
      }).eq('request_id', requestId);
    } catch (_) {}

    // 2. Call backend API to persist acceptance to MongoDB and trigger notifications
    try {
      await ApiService().acceptProblemRequest(
        requestId: requestId,
        timeSlot: slotText,
        date: date,
      );
    } catch (e) {
      debugPrint('Backend API acceptProblemRequest notice: $e');
    }

    // 3. Create & Persist Appointment in Supabase DB asynchronously in background
    if (reqObj != null) {
      ApiService().createAppointment(
        patientId: reqObj.patientName,
        dentistId: reqObj.assignedDoctorId ?? '',
        clinicId: reqObj.assignedDoctorClinic ?? '',
        date: date ?? DateTime.now().toIso8601String(),
        timeSlot: slotText,
        treatment: reqObj.problemCategory,
      ).then((_) => syncAppointmentsFromApi()).catchError((e) {
        debugPrint('Error persisting appointment in acceptReferralByDentist: $e');
      });
    }
  }

  void declineReferralByDentist(String requestId) {
    String oldDocName = 'Doctor';
    String pName = 'Patient';

    final index = _requests.indexWhere((r) => r.id == requestId || r.id.contains(requestId));
    if (index != -1) {
      final req = _requests[index];
      oldDocName = req.assignedDoctorName ?? 'Doctor';
      pName = req.patientName;
      req.status = 'Pending Admin Review';
      req.assignedDoctorId = null;
      req.assignedDoctorName = null;
      req.adminNotes = 'Declined by $oldDocName. Returned to pending review pool.';
    }

    final assignedIndex = _dentistAssignedRequests.indexWhere((r) => r.id == requestId || r.id.contains(requestId));
    if (assignedIndex != -1) {
      final req = _dentistAssignedRequests[assignedIndex];
      oldDocName = req.assignedDoctorName ?? oldDocName;
      pName = req.patientName;
      _dentistAssignedRequests.removeAt(assignedIndex);
    }

    // Dispatch Notification to Admin
    addNotification(
      recipientRole: 'Admin',
      recipientId: 'ALL_ADMINS',
      title: '⚠️ Doctor Declined Referral',
      message: '$oldDocName declined consultation for $pName. Returned to admin pool.',
    );

    _saveToStorage();
    notifyListeners();

    try {
      Supabase.instance.client.from('patient_problem_requests').update({
        'status': 'PENDING_ADMIN_REVIEW',
        'assigned_doctor_id': null,
        'assigned_doctor_name': null,
        'assigned_doctor_specialty': null,
        'assigned_doctor_clinic': null,
        'suggested_dentist_id': null,
        'admin_notes': 'Declined by $oldDocName. Returned to pending review pool.',
      }).eq('id', requestId);
    } catch (_) {}
  }

  void updateRequestStatus(String requestId, String newStatus) {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      _requests[index].status = newStatus;
      _saveToStorage();
      notifyListeners();
    }
  }

  void removeDoctor(String doctorId) {
    _allDoctors.removeWhere((d) => d.id == doctorId);
    if (currentDoctor?.id == doctorId) {
      currentDoctor = _allDoctors.firstOrNull;
    }
    _saveToStorage();
    notifyListeners();
  }

  void removePatient(String email) {
    if (currentPatient.email == email) {
      currentPatient = PatientProfile();
    }
    _requests.removeWhere((r) => r.patientName == currentPatient.name);
    _saveToStorage();
    notifyListeners();
  }

  DoctorModel registerDoctor({
    String id = '',
    required String name,
    required String email,
    required String phone,
    required String licenseNumber,
    required String specialty,
    required String clinicName,
    required int experienceYears,
    String password = 'Password123!',
    String qualification = 'BDS, MDS',
    String consultationFee = '\$75',
    Uint8List? photoBytes,
    String clinicAddress = '',
    String state = '',
    String city = '',
    String pincode = '',
    List<String>? languages,
  }) {
    if (photoBytes != null) {
      _userPhotoCache[email.trim().toLowerCase()] = photoBytes;
    }
    final cachedPhoto = photoBytes ?? _userPhotoCache[email.trim().toLowerCase()];

    final formattedName = name.trim().startsWith('Dr.') ? name.trim() : 'Dr. ${name.trim()}';
    final cleanLicense = licenseNumber.trim().isEmpty ? 'DEN-LIC-${DateTime.now().millisecondsSinceEpoch}' : licenseNumber.trim();
    final cleanClinic = clinicName.trim();
    final cleanSpecialty = specialty.trim().isEmpty ? 'General Dentistry' : specialty.trim();
    final cleanAddress = clinicAddress.trim();
    final cleanCity = city.trim();
    final cleanPincode = pincode.trim();
    final doctorLangs = (languages != null && languages.isNotEmpty) ? languages : const ['English'];

    final existingDoc = _allDoctors.firstWhere(
      (d) => d.email.trim().toLowerCase() == email.trim().toLowerCase() || (d.userId.isNotEmpty && d.userId == id) || (d.id.isNotEmpty && d.id == id),
      orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
    );
    final doctorId = existingDoc.id.isNotEmpty
        ? existingDoc.id
        : (id.trim().isNotEmpty ? id.trim() : (Supabase.instance.client.auth.currentUser?.id ?? 'DOC-${100 + _allDoctors.length + 1}'));
    final doctorUserId = existingDoc.userId.isNotEmpty
        ? existingDoc.userId
        : (id.trim().isNotEmpty ? id.trim() : (Supabase.instance.client.auth.currentUser?.id ?? ''));

    final newDoctor = DoctorModel(
      id: doctorId,
      userId: doctorUserId,
      name: formattedName.isEmpty ? (email.isNotEmpty ? email : 'Dentist') : formattedName,
      specialty: cleanSpecialty,
      qualification: qualification.trim().isEmpty ? 'BDS, MDS' : qualification.trim(),
      experienceYears: experienceYears <= 0 ? 5 : experienceYears,
      rating: 5.0,
      reviewCount: 1,
      clinicName: cleanClinic.isEmpty ? 'Independent Practice' : cleanClinic,
      phone: phone.trim().isEmpty ? '+1 202 555 0100' : phone.trim(),
      email: email.trim().isEmpty ? 'doctor@dentaguru.com' : email.trim(),
      status: 'Available',
      nextAvailableSlots: ['Today, 2:00 PM', 'Tomorrow, 10:00 AM'],
      consultationFee: consultationFee.trim().isEmpty ? '\$75' : consultationFee.trim(),
      licenseNumber: cleanLicense,
      photoBytes: cachedPhoto,
      clinicAddress: cleanAddress,
      city: cleanCity,
      pincode: cleanPincode,
      languages: doctorLangs,
    );

    if (!_allDoctors.any((d) => d.email.toLowerCase() == newDoctor.email.toLowerCase())) {
      _allDoctors.insert(0, newDoctor);
    } else {
      final idx = _allDoctors.indexWhere((d) => d.email.toLowerCase() == newDoctor.email.toLowerCase());
      if (idx != -1) _allDoctors[idx] = newDoctor;
    }

    if (currentDoctor?.id != newDoctor.id || currentDoctor?.email.toLowerCase() != newDoctor.email.toLowerCase()) {
      _dentistAssignedRequests.clear();
    }
    currentDoctor = newDoctor;

    if (cleanClinic.isNotEmpty && !_allClinics.any((c) => c.clinicName.toLowerCase() == cleanClinic.toLowerCase())) {
      _allClinics.insert(
        0,
        ClinicModel(
          id: 'CLN-${DateTime.now().millisecondsSinceEpoch}',
          clinicName: cleanClinic,
          location: cleanAddress.isNotEmpty ? (cleanCity.isNotEmpty ? '$cleanAddress, $cleanCity' : cleanAddress) : cleanCity,
          verified: true,
          services: [cleanSpecialty, 'General Dentistry', 'Root Canal'],
        ),
      );
    }

    _saveToStorage();
    syncAllDataFromApi();
    notifyListeners();

    // End-to-end Real-Time Persistence into Supabase ('users', 'clinics', 'dentists')
    ApiService().registerUser(
      name: formattedName,
      email: email.trim().isEmpty ? 'doctor_${DateTime.now().millisecondsSinceEpoch}@dentaguru.com' : email.trim(),
      password: password.trim().isEmpty ? 'Password123!' : password.trim(),
      phone: phone.trim().isEmpty ? '+91${DateTime.now().millisecondsSinceEpoch.toString().substring(3)}' : phone.trim(),
      role: 'Dentist',
      specialty: cleanSpecialty,
      licenseNumber: cleanLicense,
      clinicName: cleanClinic,
      clinicAddress: cleanAddress,
      location: cleanAddress,
      city: cleanCity,
      pincode: cleanPincode,
      qualification: qualification.trim().isEmpty ? 'BDS, MDS' : qualification.trim(),
      experienceYears: experienceYears <= 0 ? 5 : experienceYears,
      languages: doctorLangs,
    ).then((res) {
      if (res['success'] == true) {
        syncClinicsFromApi();
        syncDoctorsFromApi();
      }
    }).catchError((e) {
      debugPrint('Error syncing registered doctor/clinic to Supabase: $e');
    });

    return newDoctor;
  }

  DoctorModel? getReferringDoctorForPatient([String? patientId]) {
    // 1. Look in patient's assigned requests
    for (final req in _requests) {
      if (req.assignedDoctorId != null && req.assignedDoctorId!.isNotEmpty) {
        final doc = _allDoctors.firstWhere(
          (d) => d.id == req.assignedDoctorId || d.userId == req.assignedDoctorId || (d.name.isNotEmpty && req.assignedDoctorName != null && req.assignedDoctorName!.contains(d.name.replaceAll('Dr. ', '').trim())),
          orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
        );
        if (doc.id.isNotEmpty && doc.name.isNotEmpty) {
          return doc;
        }
      }
    }
    // 2. Return highest rated doctor or first available
    if (_allDoctors.isNotEmpty) {
      return _allDoctors.first;
    }
    return null;
  }

  void updateDoctorFeeAndSlots({
    required String doctorId,
    required String consultationFee,
    required String availableSlot,
    Map<String, String>? procedureFees,
  }) {
    final index = _allDoctors.indexWhere((d) => d.id == doctorId);
    if (index != -1) {
      final oldDoc = _allDoctors[index];
      final updatedDoc = DoctorModel(
        id: oldDoc.id,
        name: oldDoc.name,
        specialty: oldDoc.specialty,
        qualification: oldDoc.qualification,
        experienceYears: oldDoc.experienceYears,
        rating: oldDoc.rating,
        reviewCount: oldDoc.reviewCount,
        clinicName: oldDoc.clinicName,
        phone: oldDoc.phone,
        email: oldDoc.email,
        status: oldDoc.status,
        nextAvailableSlots: [availableSlot, ...oldDoc.nextAvailableSlots.skip(1)],
        consultationFee: consultationFee,
        licenseNumber: oldDoc.licenseNumber,
        photoBytes: oldDoc.photoBytes,
        clinicAddress: oldDoc.clinicAddress,
        procedureFees: procedureFees ?? oldDoc.procedureFees,
      );

      _allDoctors[index] = updatedDoc;
      if (currentDoctor?.id == doctorId || currentDoctor == null) {
        currentDoctor = updatedDoc;
      }
      _saveToStorage();
      notifyListeners();
    }
  }

  Future<void> resetToFreshState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dentaguru_patient_profile');
      await prefs.remove('dentaguru_current_doctor');
      await prefs.remove('dentaguru_requests');
      await prefs.remove('dentaguru_all_doctors');
      await prefs.remove('dentaguru_medical_records');

      currentPatient = PatientProfile();
      currentDoctor = null;
      _requests.clear();
      _allDoctors.clear();
      _medicalRecords.clear();
      _myReferrals.clear();
      _adminReferrals.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('Reset error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // REFERRAL STATE & SYNC METHODS
  // ─────────────────────────────────────────────
  List<ReferralItem> _myReferrals = [];
  ReferralStats _myReferralStats = ReferralStats();
  String _myReferralCode = '';
  List<ReferralItem> _adminReferrals = [];
  AdminReferralAnalytics _adminReferralAnalytics = AdminReferralAnalytics();

  List<ReferralItem> get myReferrals => _myReferrals;
  ReferralStats get myReferralStats => _myReferralStats;
  String get myReferralCode => _myReferralCode.isNotEmpty
      ? _myReferralCode
      : 'DG-${(currentPatient.name.isNotEmpty ? currentPatient.name.substring(0, currentPatient.name.length >= 3 ? 3 : currentPatient.name.length).toUpperCase() : "PAT")}${currentPatient.phone.isNotEmpty && currentPatient.phone.length >= 4 ? currentPatient.phone.substring(currentPatient.phone.length - 4) : "2026"}';
  List<ReferralItem> get adminReferrals => _adminReferrals;
  AdminReferralAnalytics get adminReferralAnalytics => _adminReferralAnalytics;

  Future<void> syncReferralsFromApi() async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final userId = currentPatient.id.isNotEmpty ? currentPatient.id : authUser?.id;
      final phone = currentPatient.phone.isNotEmpty ? currentPatient.phone : '';
      final code = myReferralCode;

      final res = await ApiService().fetchMyReferrals(userId: userId, userPhone: phone, referralCode: code);
      if (res['success'] == true) {
        if (res['referralCode'] != null && res['referralCode'].toString().isNotEmpty) {
          _myReferralCode = res['referralCode'].toString();
        }
        if (res['stats'] != null) {
          _myReferralStats = ReferralStats.fromJson(Map<String, dynamic>.from(res['stats']));
        }
        if (res['referrals'] is List) {
          _myReferrals = (res['referrals'] as List)
              .map((r) => ReferralItem.fromJson(Map<String, dynamic>.from(r)))
              .toList();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in syncReferralsFromApi: $e');
    }
  }

  Future<void> syncAdminReferralsFromApi() async {
    try {
      final res = await ApiService().fetchAllReferralsAdmin();
      if (res['success'] == true && res['referrals'] is List) {
        _adminReferrals = (res['referrals'] as List)
            .map((r) => ReferralItem.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      }
      final analyticsRes = await ApiService().fetchAdminReferralAnalytics();
      if (analyticsRes['success'] == true && analyticsRes['analytics'] != null) {
        _adminReferralAnalytics = AdminReferralAnalytics.fromJson(Map<String, dynamic>.from(analyticsRes['analytics']));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error in syncAdminReferralsFromApi: $e');
    }
  }
}

