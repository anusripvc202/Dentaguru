import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';
import '../models/referral_model.dart';
import '../models/doctor_availability.dart';
import '../models/medical_specialty_model.dart';

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
  final String bio;
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
    this.bio = '',
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
        'bio': bio,
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

    final parsedSpecialty = (json['specialty'] ?? json['speciality'] ?? '').toString();
    final parsedQual = (json['qualification'] ?? json['qualifications'] ?? '').toString().trim();

    return DoctorModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? (json['users'] != null ? json['users']['id'] : '') ?? '').toString(),
      name: json['name'] ?? '',
      specialty: parsedSpecialty,
      qualification: parsedQual.isNotEmpty
          ? parsedQual
          : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(parsedSpecialty),
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
      bio: (json['bio'] ?? json['about'] ?? json['description'] ?? (json['users'] is Map ? (json['users']['bio'] ?? '') : '') ?? '').toString(),
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
  String? assignedDoctorPhone;
  String? assignedDoctorFee;
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
    this.assignedDoctorPhone,
    this.assignedDoctorFee,
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
            d.userId == assignedDoctorId ||
            d.email.toLowerCase() == assignedDoctorId!.toLowerCase() ||
            (d.name.isNotEmpty && assignedDoctorId!.toLowerCase().contains(d.name.replaceAll('Dr. ', '').trim().toLowerCase())),
        orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
      );
      if (doc.name.isNotEmpty) return doc.name;
    }
    return '';
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
            d.userId == assignedDoctorId ||
            d.email.toLowerCase() == assignedDoctorId!.toLowerCase() ||
            (d.name.isNotEmpty && assignedDoctorId!.toLowerCase().contains(d.name.replaceAll('Dr. ', '').trim().toLowerCase())),
        orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
      );
      if (doc.specialty.isNotEmpty) return doc.specialty;
    }
    return '';
  }

  String get displayDoctorClinic {
    if (assignedDoctorClinic != null &&
        assignedDoctorClinic!.trim().isNotEmpty &&
        assignedDoctorClinic != 'null') {
      return assignedDoctorClinic!;
    }
    if (assignedDoctorId != null && assignedDoctorId!.isNotEmpty) {
      final doc = PatientProblemService().allDoctors.firstWhere(
        (d) =>
            d.id == assignedDoctorId ||
            d.userId == assignedDoctorId ||
            d.email.toLowerCase() == assignedDoctorId!.toLowerCase() ||
            (d.name.isNotEmpty && assignedDoctorId!.toLowerCase().contains(d.name.replaceAll('Dr. ', '').trim().toLowerCase())),
        orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
      );
      if (doc.clinicName.isNotEmpty) return doc.clinicName;
    }
    return '';
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
        'assignedDoctorPhone': assignedDoctorPhone,
        'assignedDoctorFee': assignedDoctorFee,
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
      assignedDoctorPhone: json['assignedDoctorPhone'] ?? json['suggested_dentist']?['users']?['phone'],
      assignedDoctorFee: json['assignedDoctorFee'],
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
      clinicName: (json['clinic_name'] ?? json['clinicName'] ?? 'GS HEALTH Care Center').toString(),
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
  final ApiService _api;

  // Optional injection for testing; defaults to the shared production instance.
  static final PatientProblemService _instance = PatientProblemService._internal();
  factory PatientProblemService({ApiService? api}) =>
      api == null ? _instance : PatientProblemService._internal(api);

  PatientProblemService._internal([ApiService? api]) : _api = api ?? ApiService() {
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

  void addTestDoctor(DoctorModel doc) {
    _allDoctors.add(doc);
    notifyListeners();
  }

  void addTestRequest(PatientConsultationRequest req) {
    _requests.add(req);
    notifyListeners();
  }

  // Helper to safely access auth user ID without throwing when uninitialized
  String? get _safeAuthUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  // Helper to safely access auth user email without throwing when uninitialized
  String? get _safeAuthUserEmail {
    try {
      return Supabase.instance.client.auth.currentUser?.email?.trim().toLowerCase();
    } catch (_) {
      return null;
    }
  }

  // Scoped "My Doctors" saved by the currently logged-in patient
  final Set<String> _myDoctorIds = {};

  Set<String> get myDoctorIds => Set.unmodifiable(_myDoctorIds);

  List<DoctorModel> get myDoctors {
    if (_myDoctorIds.isEmpty) return [];
    return _allDoctors.where((d) {
      return _myDoctorIds.contains(d.id) ||
             (d.userId.isNotEmpty && _myDoctorIds.contains(d.userId)) ||
             (d.email.isNotEmpty && _myDoctorIds.contains(d.email.toLowerCase())) ||
             (d.name.isNotEmpty && _myDoctorIds.contains(d.name.toLowerCase()));
    }).toList();
  }

  bool isDoctorAdded(String doctorId) {
    if (doctorId.trim().isEmpty) return false;
    final cleanId = doctorId.trim();
    if (_myDoctorIds.contains(cleanId)) return true;

    final doc = _allDoctors.firstWhere(
      (d) => d.id == cleanId || d.userId == cleanId || (d.email.isNotEmpty && d.email.toLowerCase() == cleanId.toLowerCase()),
      orElse: () => DoctorModel(
        id: '',
        name: '',
        specialty: '',
        qualification: '',
        experienceYears: 0,
        rating: 0,
        reviewCount: 0,
        clinicName: '',
        phone: '',
        email: '',
        status: '',
        nextAvailableSlots: [],
        consultationFee: '',
      ),
    );

    if (doc.id.isNotEmpty && _myDoctorIds.contains(doc.id)) return true;
    if (doc.userId.isNotEmpty && _myDoctorIds.contains(doc.userId)) return true;
    if (doc.email.isNotEmpty && _myDoctorIds.contains(doc.email.toLowerCase())) return true;
    return false;
  }

  Future<void> addDoctorToMyDoctors(DoctorModel doctor) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    final targetDocId = doctor.id.isNotEmpty ? doctor.id : (doctor.userId.isNotEmpty ? doctor.userId : doctor.email);
    if (targetDocId.isEmpty) return;

    _myDoctorIds.add(targetDocId);
    if (doctor.id.isNotEmpty) _myDoctorIds.add(doctor.id);
    if (doctor.userId.isNotEmpty) _myDoctorIds.add(doctor.userId);
    if (doctor.email.isNotEmpty) _myDoctorIds.add(doctor.email.toLowerCase());

    _saveToStorage();
    notifyListeners();

    if (pId.isNotEmpty) {
      await ApiService().addDoctorToMyDoctors(patientId: pId, doctorId: targetDocId);
    }
  }

  Future<void> removeDoctorFromMyDoctors(DoctorModel doctor) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    final targetDocId = doctor.id.isNotEmpty ? doctor.id : (doctor.userId.isNotEmpty ? doctor.userId : doctor.email);

    _myDoctorIds.remove(targetDocId);
    if (doctor.id.isNotEmpty) _myDoctorIds.remove(doctor.id);
    if (doctor.userId.isNotEmpty) _myDoctorIds.remove(doctor.userId);
    if (doctor.email.isNotEmpty) _myDoctorIds.remove(doctor.email.toLowerCase());

    _saveToStorage();
    notifyListeners();

    if (pId.isNotEmpty) {
      await ApiService().removeDoctorFromMyDoctors(patientId: pId, doctorId: targetDocId);
    }
  }

  Future<void> syncMyDoctorsFromApi() async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) return;
    try {
      final docIds = await ApiService().fetchMyDoctors(patientId: pId);
      if (docIds.isNotEmpty) {
        _myDoctorIds.addAll(docIds);
        _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync my doctors error: $e');
    }
  }

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

  // List of Issued Medical Records / Prescriptions & Patient Uploaded Dental Records
  final List<Map<String, dynamic>> _medicalRecords = [];

  List<Map<String, dynamic>> get medicalRecords => List.unmodifiable(_medicalRecords);

  // List of Patient Dental Records explicitly shared with the logged-in Doctor
  final List<Map<String, dynamic>> _doctorSharedRecords = [];

  List<Map<String, dynamic>> get doctorSharedRecords => List.unmodifiable(_doctorSharedRecords);

  void addMedicalRecord(Map<String, dynamic> record) {
    final recId = (record['id'] ?? '').toString();
    if (recId.isNotEmpty) {
      final existingIdx = _medicalRecords.indexWhere((r) => (r['id'] ?? '').toString() == recId);
      if (existingIdx != -1) {
        _medicalRecords[existingIdx] = Map<String, dynamic>.from(record);
        _saveToStorage();
        notifyListeners();
        return;
      }
    }
    _medicalRecords.insert(0, Map<String, dynamic>.from(record));
    _saveToStorage();
    notifyListeners();
  }

  /// Upload a new Patient Dental Record (JPG, JPEG, PNG, PDF) to Supabase Storage & medical_records
  Future<Map<String, dynamic>> uploadDentalRecord({
    required String recordName,
    required String category,
    String description = '',
    required Uint8List fileBytes,
    required String fileName,
    String? fileType,
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {'success': false, 'message': 'Patient session not found. Please log in again.'};
    }

    final ext = (fileType != null && fileType.trim().isNotEmpty)
        ? fileType.trim().toUpperCase()
        : (fileName.contains('.') ? fileName.split('.').last.trim().toUpperCase() : '');
    final resolvedMime = (mimeType != null && mimeType.trim().isNotEmpty)
        ? mimeType.trim()
        : (ext == 'PDF'
            ? 'application/pdf'
            : (ext == 'PNG' ? 'image/png' : 'image/jpeg'));

    final res = await ApiService().uploadPatientDentalRecord(
      patientId: pId,
      patientName: currentPatient.name,
      title: recordName,
      category: category,
      description: description,
      fileName: fileName,
      fileType: ext,
      mimeType: resolvedMime,
      fileSize: fileBytes.length,
      fileBytes: fileBytes,
      onProgress: onProgress,
    );

    if (res['success'] == true && res['record'] is Map) {
      final recordMap = Map<String, dynamic>.from(res['record'] as Map);
      addMedicalRecord(recordMap);
    }
    return res;
  }

  /// Edit an existing Patient Dental Record's metadata (name, category, description)
  Future<Map<String, dynamic>> updateDentalRecord({
    required String recordId,
    required String recordName,
    required String category,
    String description = '',
    Uint8List? newFileBytes,
    String? newFileName,
    void Function(double progress)? onProgress,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {'success': false, 'message': 'Patient session not found. Please log in again.'};
    }

    onProgress?.call(0.4);
    final res = await ApiService().updatePatientDentalRecord(
      recordId: recordId,
      patientId: pId,
      title: recordName,
      category: category,
      description: description,
    );
    onProgress?.call(1.0);

    if (res['success'] == true && res['record'] is Map) {
      final updatedMap = Map<String, dynamic>.from(res['record'] as Map);
      final idx = _medicalRecords.indexWhere((r) => (r['id'] ?? '').toString() == recordId);
      if (idx != -1) {
        _medicalRecords[idx] = updatedMap;
      } else {
        _medicalRecords.insert(0, updatedMap);
      }
      _saveToStorage();
      notifyListeners();
    }
    return res;
  }

  /// Delete a Patient Dental Record (verifies ownership & deletes storage object)
  Future<Map<String, dynamic>> deleteDentalRecord({
    required String recordId,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {'success': false, 'message': 'Patient session not found. Please log in again.'};
    }

    final res = await ApiService().deletePatientDentalRecord(
      recordId: recordId,
      patientId: pId,
    );

    if (res['success'] == true) {
      _medicalRecords.removeWhere((r) => (r['id'] ?? '').toString() == recordId);
      _doctorSharedRecords.removeWhere((r) => (r['id'] ?? '').toString() == recordId);
      _saveToStorage();
      notifyListeners();
    }
    return res;
  }

  /// Share one or multiple Patient Dental Records with a Favourite Doctor
  Future<Map<String, dynamic>> shareDentalRecordsWithDoctor({
    required List<String> recordIds,
    required DoctorModel doctor,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {'success': false, 'message': 'Patient session not found. Please log in again.'};
    }

    final targetDocId = doctor.id.isNotEmpty
        ? doctor.id
        : (doctor.userId.isNotEmpty ? doctor.userId : doctor.email);

    final res = await ApiService().shareDentalRecordsWithDoctor(
      patientId: pId,
      patientName: currentPatient.name,
      recordIds: recordIds,
      doctorId: targetDocId,
      doctorUserId: doctor.userId,
      doctorName: doctor.name,
      doctorSpecialty: doctor.specialty,
      doctorClinic: doctor.clinicName,
      doctorEmail: doctor.email,
    );

    if (res['success'] == true) {
      if (res['records'] is List) {
        for (final updated in (res['records'] as List)) {
          if (updated is Map) {
            final updatedMap = Map<String, dynamic>.from(updated);
            final id = (updatedMap['id'] ?? '').toString();
            final idx = _medicalRecords.indexWhere((r) => (r['id'] ?? '').toString() == id);
            if (idx != -1) {
              _medicalRecords[idx] = updatedMap;
            }
          }
        }
      }
      await syncMedicalRecordsFromApi();
      _saveToStorage();
      notifyListeners();
    }
    return res;
  }

  /// Revoke a Doctor's sharing permission on a Patient Dental Record
  Future<Map<String, dynamic>> revokeDentalRecordShare({
    required String recordId,
    required String doctorId,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {'success': false, 'message': 'Patient session not found. Please log in again.'};
    }

    final res = await ApiService().revokeDentalRecordShare(
      recordId: recordId,
      patientId: pId,
      doctorId: doctorId,
    );

    if (res['success'] == true) {
      if (res['record'] is Map) {
        final updatedMap = Map<String, dynamic>.from(res['record'] as Map);
        final idx = _medicalRecords.indexWhere((r) => (r['id'] ?? '').toString() == recordId);
        if (idx != -1) {
          _medicalRecords[idx] = updatedMap;
        }
      }
      _doctorSharedRecords.removeWhere(
        (r) => (r['id'] ?? '').toString() == recordId &&
            !ApiService.isDoctorAuthorizedForRecordMap(
              r,
              doctorId: doctorId,
            ),
      );
      _saveToStorage();
      notifyListeners();
    }
    return res;
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
      final authEmail = _safeAuthUserEmail;
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

      // 5c. Load My Doctors for Current Patient
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
      String? myDocStr;
      if (pId.isNotEmpty) {
        myDocStr = prefs.getString('dentaguru_my_doctor_ids_$pId');
      }
      myDocStr ??= prefs.getString('dentaguru_my_doctor_ids');
      if (myDocStr != null && myDocStr.isNotEmpty) {
        try {
          final List list = jsonDecode(myDocStr);
          _myDoctorIds.clear();
          _myDoctorIds.addAll(list.map((e) => e.toString()));
        } catch (_) {}
      }

      // 6. Sync live patients, appointments, clinics, doctors, records, specialties, and requests directly from Supabase DB API
      final savedSpecsJson = prefs.getString('dentaguru_medical_specialties');
      if (savedSpecsJson != null && savedSpecsJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(savedSpecsJson);
          final parsed = decoded
              .whereType<Map>()
              .map((m) => MedicalSpecialtyModel.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          if (parsed.isNotEmpty) {
            _specialties = parsed;
          }
        } catch (_) {}
      }

      final savedDeptsJson = prefs.getString('dentaguru_clinic_departments');
      if (savedDeptsJson != null && savedDeptsJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(savedDeptsJson);
          _clinicDepartments
            ..clear()
            ..addAll(decoded.map((e) => e.toString()));
        } catch (_) {}
      }

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
        syncSpecialtiesFromApi(),
        syncPatientsFromApi(),
        syncClinicsFromApi(),
        syncDoctorsFromApi(),
        syncMedicalRecordsFromApi(),
        syncSubAdminsFromApi(),
        syncMyDoctorsFromApi(),
      ]);
      await Future.wait([
        syncAppointmentsFromApi(),
        syncProblemRequestsFromApi(),
        syncDentistAssignedRequestsFromApi(),
        syncReferralsFromApi(),
        syncDoctorReferralsFromApi(),
        syncAdminReferralsFromApi(),
        syncNotificationsFromApi(),
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
    _doctorSharedRecords.clear();
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

          final isActualAdmin = (role.contains('admin') && !email.contains('patient'));
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
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : _safeAuthUserId;
      if (pId != null && pId.isNotEmpty) {
        final apiRecords = await ApiService().fetchMedicalRecords(patientId: pId);
        // Preserve any records belonging to other patients or local-only slips while replacing current patient's DB records with fresh API snapshot
        final apiIds = <String>{};
        final freshMaps = <Map<String, dynamic>>[];
        for (final item in apiRecords) {
          if (item is Map) {
            final itemMap = Map<String, dynamic>.from(item);
            final id = (itemMap['id'] ?? '').toString();
            if (id.isNotEmpty) apiIds.add(id);
            freshMaps.add(itemMap);
          }
        }

        // Update or insert fresh records from API
        for (final fresh in freshMaps) {
          final id = (fresh['id'] ?? '').toString();
          if (id.isNotEmpty) {
            final existingIdx = _medicalRecords.indexWhere((r) => (r['id'] ?? '').toString() == id);
            if (existingIdx != -1) {
              _medicalRecords[existingIdx] = fresh;
            } else {
              _medicalRecords.insert(0, fresh);
            }
          }
        }
        _saveToStorage();
        notifyListeners();
      }

      if (_isDentistMode || currentDoctor != null) {
        await syncDoctorSharedRecordsFromApi();
      }
    } catch (e) {
      debugPrint('Sync medical records error: $e');
    }
  }

  /// Sync patient dental records explicitly shared with the currently logged-in Doctor
  Future<List<Map<String, dynamic>>> syncDoctorSharedRecordsFromApi({String? patientId}) async {
    try {
      final doc = currentDoctor;
      final dId = (doc != null && doc.id.isNotEmpty)
          ? doc.id
          : ((doc != null && doc.userId.isNotEmpty) ? doc.userId : (_safeAuthUserId ?? ''));
      final dUserId = doc?.userId.isNotEmpty == true ? doc!.userId : _safeAuthUserId;
      final dEmail = doc?.email.isNotEmpty == true ? doc!.email : _safeAuthUserEmail;

      if (dId.isEmpty && (dEmail == null || dEmail.isEmpty)) {
        return [];
      }

      final sharedList = await ApiService().fetchSharedRecordsForDoctor(
        doctorId: dId.isNotEmpty ? dId : dEmail!,
        doctorUserId: dUserId,
        doctorEmail: dEmail,
        patientId: patientId,
      );

      // Enrich patientName from _allPatients if needed
      for (final rec in sharedList) {
        final recPid = (rec['patientId'] ?? rec['patient_id'] ?? '').toString();
        final curPName = (rec['patientName'] ?? '').toString();
        if ((curPName.isEmpty || curPName == 'Patient') && recPid.isNotEmpty) {
          final matchP = _allPatients.firstWhere(
            (p) => p.id == recPid,
            orElse: () => PatientProfile(),
          );
          if (matchP.name.isNotEmpty) {
            rec['patientName'] = matchP.name;
            rec['patientPhone'] = matchP.phone;
            rec['patientEmail'] = matchP.email;
          }
        }
      }

      if (patientId == null || patientId.trim().isEmpty) {
        _doctorSharedRecords
          ..clear()
          ..addAll(sharedList);
      } else {
        _doctorSharedRecords.removeWhere((r) => (r['patientId'] ?? r['patient_id'] ?? '').toString() == patientId.trim());
        _doctorSharedRecords.insertAll(0, sharedList);
      }
      notifyListeners();
      return List<Map<String, dynamic>>.from(sharedList);
    } catch (e) {
      debugPrint('Sync doctor shared records error: $e');
      return [];
    }
  }

  bool _isDentistMode = false;
  void setDentistMode(bool enabled) {
    _isDentistMode = enabled;
    if (enabled) {
      syncProblemRequestsFromApi();
      syncDoctorSharedRecordsFromApi();
    }
  }

  Future<void> syncProblemRequestsFromApi() async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : authUser?.id;
      final pEmail = currentPatient.email.isNotEmpty ? currentPatient.email : authUser?.email;
      final currentPName = currentPatient.name;

      final isAdmin = _isAdminMode ||
                      (authUser?.email != null && authUser!.email!.toLowerCase().contains('admin')) ||
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
          final phone = (userObj['phone'] ?? dMap['phone'] ?? '').toString();
          final specialty = (dMap['speciality'] ?? dMap['specialty'] ?? 'General Dentistry').toString();
          final licNum = (dMap['license_number'] ?? dMap['licenseNumber'] ?? 'DEN-LIC-REG').toString();
          final cName = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString();
          final cLoc = (clinicObj['location'] ?? dMap['location'] ?? '').toString();
          final docBio = (dMap['bio'] ?? dMap['about'] ?? dMap['description'] ?? userObj['bio'] ?? '').toString();

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

          Uint8List? docPhotoBytes;
          final rawPhoto = (userObj['biometric_token'] ?? dMap['profile_photo'] ?? dMap['photo'] ?? dMap['avatar'] ?? userObj['avatar'] ?? '').toString();
          if (rawPhoto.isNotEmpty && rawPhoto.length > 20) {
            try {
              final cleanBase64 = rawPhoto.contains(',') ? rawPhoto.split(',').last : rawPhoto;
              docPhotoBytes = base64Decode(cleanBase64);
            } catch (_) {}
          }

          final rawSlots = dMap['slots'] ?? dMap['available_slots'] ?? dMap['nextAvailableSlots'];
          final List<String> parsedSlots = rawSlots is List
              ? rawSlots.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList()
              : <String>[];

          _allDoctors.add(DoctorModel(
            id: id.isNotEmpty ? id : 'DOC-${100 + _allDoctors.length + 1}',
            userId: doctorUserId,
            name: formattedName,
            specialty: specialty,
            qualification: (dMap['qualifications'] ?? dMap['qualification'] ?? 'BDS, MDS').toString(),
            experienceYears: int.tryParse((dMap['experience_years'] ?? dMap['experienceYears'] ?? '5').toString()) ?? 5,
            rating: (dMap['rating'] ?? 5.0).toDouble(),
            reviewCount: dMap['reviews_count'] ?? 1,
            clinicName: cName,
            clinicAddress: cLoc,
            phone: phone,
            email: email,
            status: (dMap['availability_status'] ?? 'Available').toString(),
            nextAvailableSlots: parsedSlots,
            consultationFee: (dMap['consultation_fee'] ?? dMap['consultationFee'] ?? '₹500').toString(),
            licenseNumber: licNum,
            photoBytes: docPhotoBytes,
            state: doctorState,
            city: doctorCity,
            pincode: doctorPincode,
            bio: docBio,
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
        final isAdmin = (authUser?.email != null && authUser!.email!.toLowerCase().contains('admin')) ||
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
        final rawDate = (item['date'] ?? item['appointment_date'] ?? item['appointmentDate'])?.toString();
        final statusStr = (item['status'] ?? 'CONFIRMED').toString();

        final existingIndex = _requests.indexWhere((r) =>
            r.id == reqId ||
            (itemPatientId != null && itemPatientId.isNotEmpty && r.patientId != null && r.patientId == itemPatientId && r.problemCategory.trim().toLowerCase() == treatment.toString().trim().toLowerCase() && r.confirmedTimeSlot == slot?.toString()) ||
            (pName.isNotEmpty && pName.toLowerCase() != 'patient' && r.patientName.trim().toLowerCase() == pName.trim().toLowerCase() && r.problemCategory.trim().toLowerCase() == treatment.toString().trim().toLowerCase() && r.confirmedTimeSlot == slot?.toString()) ||
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
          if (rawDate != null && rawDate.isNotEmpty) {
            _requests[existingIndex].confirmedDate = rawDate;
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
              confirmedDate: rawDate,
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
        final isRealUuid = r.id.isNotEmpty && !r.id.startsWith('PR-') && !r.id.startsWith('REQ-');
        final key = isRealUuid
            ? r.id
            : ((pKey.isNotEmpty && catKey.isNotEmpty) ? '${pKey}_${catKey}_${r.confirmedTimeSlot ?? ''}_${r.confirmedDate ?? ''}' : r.id);

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
            confirmedDate: (r.confirmedDate != null && r.confirmedDate!.isNotEmpty) ? r.confirmedDate : existing.confirmedDate,
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

  /// Book a new appointment directly with selected doctor & time slot
  Future<Map<String, dynamic>> bookAppointment({
    required String dentistId,
    String clinicId = '',
    required String date,
    required String timeSlot,
    required String treatment,
    String symptoms = '',
  }) async {
    final cleanDate = date.contains('T') ? date.split('T').first : date.trim();
    final cleanSlot = timeSlot.trim();
    if (dentistId.trim().isEmpty || cleanDate.isEmpty || cleanSlot.isEmpty) {
      return {
        'success': false,
        'message': 'Please select an available date and time slot.',
      };
    }

    final matchedDoc = _allDoctors.firstWhere(
      (d) => d.id == dentistId || (d.userId.isNotEmpty && d.userId == dentistId),
      orElse: () => DoctorModel(
        id: dentistId,
        name: '',
        specialty: '',
        qualification: '',
        experienceYears: 0,
        rating: 0,
        reviewCount: 0,
        clinicName: '',
        phone: '',
        email: '',
        status: '',
        nextAvailableSlots: const [],
        consultationFee: '',
      ),
    );

    // Prevent double booking in local state before submitting
    final alreadyBooked = _requests.any((req) {
      final matchesDoc = req.assignedDoctorId == dentistId ||
          (matchedDoc.id.isNotEmpty && req.assignedDoctorId == matchedDoc.id) ||
          (matchedDoc.userId.isNotEmpty && req.assignedDoctorId == matchedDoc.userId) ||
          (matchedDoc.name.isNotEmpty && req.assignedDoctorName == matchedDoc.name);
      if (!matchesDoc) return false;
      final s = req.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED') return false;
      final rDate = req.confirmedDate?.split('T').first ?? req.submittedAt.toIso8601String().split('T').first;
      return rDate == cleanDate && (req.confirmedTimeSlot?.trim().toLowerCase() == cleanSlot.toLowerCase());
    });

    final cachedAvail = _availabilityCache['${dentistId}_$cleanDate'];
    if (alreadyBooked ||
        (cachedAvail != null &&
            (cachedAvail.isBlocked ||
                cachedAvail.bookedSlots.any((b) => b.toLowerCase() == cleanSlot.toLowerCase())))) {
      return {
        'success': false,
        'message': 'The selected time slot ($cleanSlot) is no longer available. Please choose another slot.',
      };
    }

    final pId = currentPatient.id.isNotEmpty
        ? currentPatient.id
        : (_safeAuthUserId ?? '');
    final res = await _api.createAppointment(
      patientId: pId,
      dentistId: dentistId,
      clinicId: clinicId,
      date: cleanDate,
      timeSlot: cleanSlot,
      treatment: treatment,
    );

    final isExplicitSlotConflict = res['success'] == false &&
        (res['message']?.toString().toLowerCase().contains('already booked') == true ||
         res['message']?.toString().toLowerCase().contains('blocked') == true ||
         res['message']?.toString().toLowerCase().contains('unavailable') == true);

    if (isExplicitSlotConflict) {
      return res;
    }

    // Record appointment in local _requests and update availability cache immediately
    final apptMap = res['appointment'] is Map ? Map<String, dynamic>.from(res['appointment']) : <String, dynamic>{};
    final apptId = (apptMap['id'] ?? apptMap['_id'] ?? 'APT-${DateTime.now().millisecondsSinceEpoch}').toString();
    final pName = currentPatient.name.trim().isNotEmpty ? currentPatient.name.trim() : 'Patient';

    final existingIdx = _requests.indexWhere((r) => r.id == apptId);
    final newReq = PatientConsultationRequest(
      id: apptId,
      patientId: pId.isNotEmpty ? pId : null,
      patientName: pName,
      patientPhone: currentPatient.phone,
      problemCategory: treatment.trim().isNotEmpty ? treatment.trim() : 'Dental Consultation',
      problemDescription: symptoms.trim().isNotEmpty ? symptoms.trim() : 'Scheduled dental consultation',
      symptoms: symptoms.trim(),
      severity: 'Moderate',
      submittedAt: DateTime.now(),
      status: 'Confirmed',
      assignedDoctorId: matchedDoc.id.isNotEmpty ? matchedDoc.id : dentistId,
      assignedDoctorName: matchedDoc.name.isNotEmpty ? matchedDoc.name : null,
      assignedDoctorSpecialty: matchedDoc.specialty.isNotEmpty ? matchedDoc.specialty : 'Dental Specialist',
      assignedDoctorClinic: matchedDoc.clinicName.isNotEmpty ? matchedDoc.clinicName : (clinicId.isNotEmpty ? clinicId : null),
      assignedDoctorPhone: matchedDoc.phone,
      assignedDoctorFee: matchedDoc.consultationFee,
      confirmedDate: cleanDate,
      confirmedTimeSlot: cleanSlot,
      city: currentPatient.city.isNotEmpty ? currentPatient.city : matchedDoc.city,
      pincode: currentPatient.pincode.isNotEmpty ? currentPatient.pincode : matchedDoc.pincode,
      state: currentPatient.state.isNotEmpty ? currentPatient.state : matchedDoc.state,
      whatsappNotificationSent: true,
    );

    if (existingIdx != -1) {
      _requests[existingIdx] = newReq;
    } else {
      _requests.insert(0, newReq);
    }

    if (cachedAvail != null) {
      final updatedBooked = List<String>.from(cachedAvail.bookedSlots);
      if (!updatedBooked.any((b) => b.toLowerCase() == cleanSlot.toLowerCase())) {
        updatedBooked.add(cleanSlot);
      }
      final updatedAvailable = cachedAvail.allSlots
          .where((s) => !updatedBooked.any((b) => b.toLowerCase() == s.toLowerCase()))
          .toList();
      _availabilityCache['${dentistId}_$cleanDate'] = cachedAvail.copyWith(
        bookedSlots: updatedBooked,
        availableSlots: updatedAvailable,
      );
    }

    if (res['success'] == true) {
      await syncAppointmentsFromApi();
    }
    _saveToStorage();
    notifyListeners();
    return {
      'success': true,
      'message': res['message'] ?? 'Appointment booked successfully.',
      'appointment': apptMap.isNotEmpty ? apptMap : {
        'id': apptId,
        'patient_id': pId,
        'dentist_id': dentistId,
        'date': cleanDate,
        'time_slot': cleanSlot,
        'treatment': treatment,
        'status': 'CONFIRMED',
      },
    };
  }

  /// Reschedule an existing appointment
  Future<Map<String, dynamic>> rescheduleAppointment({
    required String appointmentId,
    required String date,
    required String timeSlot,
  }) async {
    final res = await _api.rescheduleAppointment(
      appointmentId: appointmentId,
      date: date,
      timeSlot: timeSlot,
    );
    if (res['success'] == true) {
      await syncAppointmentsFromApi();
      notifyListeners();
    }
    return res;
  }

  /// Cancel an existing appointment
  Future<Map<String, dynamic>> cancelAppointment(String appointmentId) async {
    final res = await _api.cancelAppointment(appointmentId);
    if (res['success'] == true) {
      final idx = _requests.indexWhere((r) => r.id == appointmentId);
      if (idx != -1) {
        _requests[idx].status = 'CANCELLED';
      }
      await syncAppointmentsFromApi();
      notifyListeners();
    }
    return res;
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
      await prefs.setString('dentaguru_medical_specialties', jsonEncode(_specialties.map((s) => s.toJson()).toList()));
      await prefs.setString('dentaguru_clinic_departments', jsonEncode(_clinicDepartments));

      // Persist My Doctors isolated per Patient
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
      if (pId.isNotEmpty) {
        await prefs.setString('dentaguru_my_doctor_ids_$pId', jsonEncode(_myDoctorIds.toList()));
      }
      await prefs.setString('dentaguru_my_doctor_ids', jsonEncode(_myDoctorIds.toList()));

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
      _doctorSharedRecords.clear();
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
      _doctorSharedRecords.clear();
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
    String? preferredDoctorId,
    String? preferredDoctorName,
    String? preferredDoctorClinic,
    String? referringDentistId,
    String? referringDentistName,
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

    final bool isDirectReferral = preferredDoctorId != null && preferredDoctorId.isNotEmpty;

    // Resolve doctor details if this is a referral
    DoctorModel? doc;
    if (isDirectReferral) {
      final matchIdx = _allDoctors.indexWhere(
        (d) => d.id == preferredDoctorId || d.userId == preferredDoctorId || (preferredDoctorName != null && d.name.toLowerCase().contains(preferredDoctorName.toLowerCase())),
      );
      if (matchIdx != -1) {
        doc = _allDoctors[matchIdx];
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
      status: isDirectReferral ? 'DENTIST_ASSIGNED' : 'PENDING_ADMIN_REVIEW',
      city: pCity,
      pincode: pPincode,
      state: pState,
      preferredDoctorId: preferredDoctorId,
      preferredDoctorName: preferredDoctorName ?? doc?.name,
      preferredDoctorClinic: preferredDoctorClinic ?? doc?.clinicName,
      assignedDoctorId: isDirectReferral ? (doc?.id ?? preferredDoctorId) : null,
      assignedDoctorName: isDirectReferral ? (doc?.name ?? preferredDoctorName) : null,
      assignedDoctorSpecialty: isDirectReferral ? (doc?.specialty.isNotEmpty == true ? doc!.specialty : problemCategory) : null,
      assignedDoctorClinic: isDirectReferral ? (doc?.clinicName ?? preferredDoctorClinic) : null,
      assignedDoctorPhone: isDirectReferral ? (doc?.phone ?? '') : null,
      assignedDoctorFee: isDirectReferral ? (doc?.consultationFee.isNotEmpty == true ? doc!.consultationFee : '₹500') : null,
      adminNotes: isDirectReferral ? 'Referral directly assigned to ${doc?.name ?? preferredDoctorName}' : null,
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
        preferredDoctorId: preferredDoctorId,
        preferredDoctorName: preferredDoctorName,
        preferredDoctorClinic: preferredDoctorClinic,
        referringDentistId: referringDentistId,
        referringDentistName: referringDentistName,
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
        clinicName: req.assignedDoctorClinic ?? 'GS HEALTH Care Center',
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

    // 2. Call backend API to persist acceptance to Supabase PostgreSQL and trigger notifications
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

  Future<void> deleteDoctor(String doctorId) async {
    _allDoctors.removeWhere((d) => d.id == doctorId || d.userId == doctorId);
    if (currentDoctor?.id == doctorId || currentDoctor?.userId == doctorId) {
      currentDoctor = _allDoctors.firstOrNull;
    }
    _saveToStorage();
    notifyListeners();

    try {
      await ApiService().deleteDoctor(doctorId);
    } catch (e) {
      debugPrint('PatientProblemService deleteDoctor error: $e');
    }
  }

  void removeDoctor(String doctorId) {
    deleteDoctor(doctorId);
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
    double? latitude,
    double? longitude,
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
      latitude: latitude,
      longitude: longitude,
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

  // Complete Patient -> Patient -> Doctor Referrals
  List<PatientReferral> _myCreatedPatientReferrals = [];
  List<PatientReferral> _doctorReceivedPatientReferrals = [];
  List<PatientReferral> _receivedForMePatientReferrals = [];
  List<PatientReferral> _adminPatientReferrals = [];

  List<ReferralItem> get myReferrals => _myReferrals;
  ReferralStats get myReferralStats => _myReferralStats;
  String get myReferralCode => _myReferralCode.isNotEmpty
      ? _myReferralCode
      : 'DG-${(currentPatient.name.isNotEmpty ? currentPatient.name.substring(0, currentPatient.name.length >= 3 ? 3 : currentPatient.name.length).toUpperCase() : "PAT")}${currentPatient.phone.isNotEmpty && currentPatient.phone.length >= 4 ? currentPatient.phone.substring(currentPatient.phone.length - 4) : "2026"}';
  List<ReferralItem> get adminReferrals => _adminReferrals;
  List<PatientReferral> get adminPatientReferrals => List.unmodifiable(_adminPatientReferrals);
  AdminReferralAnalytics get adminReferralAnalytics => _adminReferralAnalytics;

  List<PatientReferral> get myCreatedPatientReferrals => List.unmodifiable(_myCreatedPatientReferrals);
  List<PatientReferral> get doctorReceivedPatientReferrals => List.unmodifiable(_doctorReceivedPatientReferrals);
  List<PatientReferral> get receivedForMePatientReferrals => List.unmodifiable(_receivedForMePatientReferrals);

  /// Sync Patient Referrals created by the logged-in patient or dentist
  Future<void> syncReferralsFromApi({String? overrideUserId}) async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final doc = currentDoctor;
      final userId = overrideUserId ??
          (doc != null && doc.id.isNotEmpty
              ? (doc.userId.isNotEmpty ? doc.userId : doc.id)
              : (currentPatient.id.isNotEmpty ? currentPatient.id : authUser?.id));
      final phone = (doc != null && doc.phone.isNotEmpty) ? doc.phone : (currentPatient.phone.isNotEmpty ? currentPatient.phone : '');
      final code = myReferralCode;

      // 1. Fetch organic invites
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
      }

      // 2. Fetch Patient Referrals (Patient A -> Patient B -> Doctor C or Doctor A -> Doctor B)
      final rawPatientRefs = await ApiService().fetchMyPatientReferrals(userId: userId);
      _myCreatedPatientReferrals.clear();
      for (final r in rawPatientRefs) {
        try {
          _myCreatedPatientReferrals.add(PatientReferral.fromJson(Map<String, dynamic>.from(r)));
        } catch (_) {}
      }

      // 3. Fetch referrals where this user is the referred patient
      final rawReceived = await ApiService().fetchReceivedPatientReferrals(patientId: userId, patientPhone: phone);
      _receivedForMePatientReferrals.clear();
      for (final r in rawReceived) {
        try {
          _receivedForMePatientReferrals.add(PatientReferral.fromJson(Map<String, dynamic>.from(r)));
        } catch (_) {}
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error in syncReferralsFromApi: $e');
    }
  }

  /// Sync Referrals received by Doctor (Doctor isolation)
  Future<void> syncDoctorReferralsFromApi({String? doctorId}) async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final authEmail = authUser?.email?.trim().toLowerCase();
      final authName = (authUser?.userMetadata?['name'] ?? '').toString().toLowerCase();

      // Auto-resolve currentDoctor if needed
      if (currentDoctor == null && authEmail != null && authEmail.isNotEmpty) {
        final match = allDoctors.where((d) =>
          d.email.toLowerCase() == authEmail ||
          (d.id.isNotEmpty && d.id == authUser?.id) ||
          (d.userId.isNotEmpty && d.userId == authUser?.id) ||
          (authName.isNotEmpty && d.name.toLowerCase().contains(authName))
        ).firstOrNull;
        if (match != null) {
          currentDoctor = match;
        }
      }

      final doc = currentDoctor;
      final docNameClean = (doc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      final docClinicClean = (doc?.clinicName ?? '').trim().toLowerCase();

      final doctorIds = <String>{
        if (doctorId != null && doctorId.isNotEmpty) doctorId,
        if (doc?.id != null && doc!.id.isNotEmpty) doc.id,
        if (doc?.userId != null && doc!.userId.isNotEmpty) doc.userId,
        if (authUser?.id != null && authUser!.id.isNotEmpty) authUser.id,
        if (doc?.email != null && doc!.email.isNotEmpty) doc.email.toLowerCase(),
        if (authEmail != null && authEmail.isNotEmpty) authEmail,
      };

      for (final d in allDoctors) {
        if (doctorIds.contains(d.id) || (d.userId.isNotEmpty && doctorIds.contains(d.userId)) || (d.email.isNotEmpty && doctorIds.contains(d.email.toLowerCase()))) {
          if (d.id.isNotEmpty) doctorIds.add(d.id);
          if (d.userId.isNotEmpty) doctorIds.add(d.userId);
          if (d.email.isNotEmpty) doctorIds.add(d.email.toLowerCase());
        }
      }

      final Map<String, PatientReferral> resultMap = {};

      // 1. Primary doctor referrals fetch from ApiService
      try {
        final raw = await ApiService().fetchDoctorPatientReferrals(doctorId: doctorIds.firstOrNull);
        for (final r in raw) {
          try {
            final pref = PatientReferral.fromJson(Map<String, dynamic>.from(r));
            if (pref.id.isNotEmpty) resultMap[pref.id] = pref;
          } catch (_) {}
        }
      } catch (_) {}

      // 2. Cross-reference adminPatientReferrals pool
      for (final ref in _adminPatientReferrals) {
        final rDocId = ref.doctorId.trim();
        final rDocName = ref.doctorName.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
        final rClinic = ref.doctorClinicName.trim().toLowerCase();

        final matchId = rDocId.isNotEmpty && doctorIds.contains(rDocId);
        final matchName = docNameClean.isNotEmpty && rDocName.isNotEmpty && (docNameClean == rDocName || docNameClean.contains(rDocName) || rDocName.contains(docNameClean));
        final matchClinic = docClinicClean.isNotEmpty && rClinic.isNotEmpty && (docClinicClean == rClinic || docClinicClean.contains(rClinic));

        if (matchId || matchName || matchClinic) {
          if (ref.id.isNotEmpty && !resultMap.containsKey(ref.id)) {
            resultMap[ref.id] = ref;
          }
        }
      }

      _doctorReceivedPatientReferrals.clear();
      _doctorReceivedPatientReferrals.addAll(resultMap.values);
      notifyListeners();
    } catch (e) {
      debugPrint('Error in syncDoctorReferralsFromApi: $e');
    }
  }

  /// Get patients associated with the currently logged-in dentist (excluding unrelated patients)
  List<PatientProfile> getDentistAssociatedPatients() {
    var doc = currentDoctor;
    final authUser = Supabase.instance.client.auth.currentUser;
    final authEmail = authUser?.email?.trim().toLowerCase();
    final authName = (authUser?.userMetadata?['name'] ?? '').toString().toLowerCase();

    if (doc == null && authEmail != null && authEmail.isNotEmpty) {
      final match = allDoctors.where((d) =>
        d.email.toLowerCase() == authEmail ||
        (d.id.isNotEmpty && d.id == authUser?.id) ||
        (d.userId.isNotEmpty && d.userId == authUser?.id) ||
        (authName.isNotEmpty && d.name.toLowerCase().contains(authName))
      ).firstOrNull;
      if (match != null) {
        doc = match;
      }
    }

    final docNameClean = (doc?.name ?? '').replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
    final docId = (doc?.id ?? '').trim();
    final docUserId = (doc?.userId ?? '').trim();
    final docEmail = (doc?.email ?? '').trim().toLowerCase();
    final authUserId = (authUser?.id ?? '').trim();

    final myDoctorIds = <String>{
      if (docId.isNotEmpty) docId,
      if (docUserId.isNotEmpty) docUserId,
      if (authUserId.isNotEmpty) authUserId,
      if (docEmail.isNotEmpty) docEmail,
      if (authEmail != null && authEmail.isNotEmpty) authEmail,
    };

    for (final d in allDoctors) {
      if (myDoctorIds.contains(d.id) || (d.userId.isNotEmpty && myDoctorIds.contains(d.userId)) || (d.email.isNotEmpty && myDoctorIds.contains(d.email.toLowerCase()))) {
        if (d.id.isNotEmpty) myDoctorIds.add(d.id);
        if (d.userId.isNotEmpty) myDoctorIds.add(d.userId);
        if (d.email.isNotEmpty) myDoctorIds.add(d.email.toLowerCase());
      }
    }

    bool isAssignedToMe(PatientConsultationRequest r) {
      final aId = r.assignedDoctorId?.trim();
      if (aId != null && aId.isNotEmpty && myDoctorIds.contains(aId)) {
        return true;
      }
      final aName = r.assignedDoctorName?.replaceAll('Dr.', '').replaceAll('Dr. ', '').trim().toLowerCase();
      if (docNameClean.isNotEmpty &&
          aName != null && aName.isNotEmpty && (aName == docNameClean || docNameClean.contains(aName) || aName.contains(docNameClean))) {
        return true;
      }
      return false;
    }

    final Map<String, PatientProfile> associatedMap = {};

    // 1. From dentist assigned requests & timeline requests
    final allPool = [
      ..._dentistAssignedRequests,
      ..._requests.where((r) => isAssignedToMe(r)),
    ];

    for (final req in allPool) {
      if (req.patientName.trim().isEmpty) continue;
      final cleanPhone = req.patientPhone.replaceAll(RegExp(r'[^0-9]'), '');
      final raw10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      final key = raw10.isNotEmpty ? raw10 : req.patientName.trim().toLowerCase();

      PatientProfile? matchedProfile = _allPatients.where((p) {
        final pPhone = p.phone.replaceAll(RegExp(r'[^0-9]'), '');
        return (raw10.isNotEmpty && pPhone.contains(raw10)) ||
            p.name.trim().toLowerCase() == req.patientName.trim().toLowerCase();
      }).firstOrNull;

      associatedMap[key] = PatientProfile(
        id: matchedProfile?.id.isNotEmpty == true ? matchedProfile!.id : (req.id.isNotEmpty ? req.id : 'pat_${req.patientName.hashCode}'),
        name: req.patientName.trim(),
        phone: raw10.isNotEmpty ? raw10 : (matchedProfile?.phone.isNotEmpty == true ? matchedProfile!.phone : req.patientPhone),
        email: matchedProfile?.email.isNotEmpty == true ? matchedProfile!.email : (raw10.isNotEmpty ? 'user_$raw10@dentaguru.internal' : ''),
        age: (matchedProfile?.age.isNotEmpty == true) ? matchedProfile!.age : '28',
        gender: (matchedProfile?.gender.isNotEmpty == true) ? matchedProfile!.gender : 'Female',
        city: req.city.isNotEmpty ? req.city : (matchedProfile?.city.isNotEmpty == true ? matchedProfile!.city : 'Hyderabad'),
        pincode: req.pincode.isNotEmpty ? req.pincode : (matchedProfile?.pincode.isNotEmpty == true ? matchedProfile!.pincode : ''),
        address: req.preferredLocation.isNotEmpty ? req.preferredLocation : (matchedProfile?.address.isNotEmpty == true ? matchedProfile!.address : req.state),
        emergencyContact: req.problemDescription.isNotEmpty ? req.problemDescription : (matchedProfile?.emergencyContact ?? ''),
      );
    }

    // 2. From doctor received referrals
    for (final ref in _doctorReceivedPatientReferrals) {
      if (ref.referredPatientName.trim().isEmpty) continue;
      final cleanPhone = ref.referredPatientMobile.replaceAll(RegExp(r'[^0-9]'), '');
      final raw10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      final key = raw10.isNotEmpty ? raw10 : ref.referredPatientName.trim().toLowerCase();

      if (!associatedMap.containsKey(key)) {
        associatedMap[key] = PatientProfile(
          id: ref.referredPatientId ?? 'ref_pat_${ref.id}',
          name: ref.referredPatientName.trim(),
          phone: raw10.isNotEmpty ? raw10 : ref.referredPatientMobile,
          email: raw10.isNotEmpty ? 'user_$raw10@dentaguru.internal' : '',
          age: ref.referredPatientAge.isNotEmpty ? ref.referredPatientAge : '28',
          gender: ref.referredPatientGender.isNotEmpty ? ref.referredPatientGender : 'Female',
          city: ref.referredPatientCity.isNotEmpty ? ref.referredPatientCity : 'Hyderabad',
          pincode: ref.referredPatientPincode.isNotEmpty ? ref.referredPatientPincode : '',
          address: ref.referredPatientLocation.isNotEmpty ? ref.referredPatientLocation : '',
          emergencyContact: ref.clinicalComplaint,
        );
      }
    }

    return associatedMap.values.toList();
  }

  /// Submit a new Patient Referral (supports Patient Referrer and Dentist Referrer)
  Future<Map<String, dynamic>> submitPatientReferral({
    required String referredPatientName,
    required String referredPatientMobile,
    required String referredPatientAge,
    required String referredPatientGender,
    required String referredPatientCity,
    required String referredPatientPincode,
    required String referredPatientLocation,
    required String requiredSpecialist,
    required String clinicalComplaint,
    required String doctorId,
    String? referrerPatientId,
    String? doctorName,
    String? doctorClinicName,
    String? doctorLocation,
    String? doctorCity,
    String? doctorPincode,
    String? doctorPhone,
  }) async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final doc = currentDoctor;
      final referrerId = referrerPatientId ??
          (doc != null && doc.id.isNotEmpty
              ? (doc.userId.isNotEmpty ? doc.userId : doc.id)
              : (currentPatient.id.isNotEmpty ? currentPatient.id : authUser?.id));

      final res = await ApiService().createPatientReferral(
        referredPatientName: referredPatientName,
        referredPatientMobile: referredPatientMobile,
        referredPatientAge: referredPatientAge,
        referredPatientGender: referredPatientGender,
        referredPatientCity: referredPatientCity,
        referredPatientPincode: referredPatientPincode,
        referredPatientLocation: referredPatientLocation,
        requiredSpecialist: requiredSpecialist,
        clinicalComplaint: clinicalComplaint,
        doctorId: doctorId,
        referrerPatientId: referrerId,
        doctorName: doctorName,
        doctorClinicName: doctorClinicName,
        doctorLocation: doctorLocation,
        doctorCity: doctorCity,
        doctorPincode: doctorPincode,
        doctorPhone: doctorPhone,
      );

      if (res['success'] == true && res['referral'] != null) {
        try {
          final newRef = PatientReferral.fromJson(Map<String, dynamic>.from(res['referral']));
          _myCreatedPatientReferrals.insert(0, newRef);

          // Add referred patient to _allPatients if not present
          final cleanPhone = referredPatientMobile.replaceAll(RegExp(r'[^0-9]'), '');
          final raw10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
          final alreadyInList = _allPatients.any((p) => (p.phone.isNotEmpty && p.phone.contains(raw10)) || (p.name.toLowerCase() == referredPatientName.trim().toLowerCase()));
          if (!alreadyInList) {
            _allPatients.insert(
              0,
              PatientProfile(
                id: newRef.referredPatientId ?? 'pat_${DateTime.now().millisecondsSinceEpoch}',
                name: referredPatientName.trim(),
                phone: raw10,
                email: 'user_$raw10@dentaguru.internal',
                age: referredPatientAge.trim(),
                gender: referredPatientGender.trim(),
                city: referredPatientCity.trim(),
                pincode: referredPatientPincode.trim(),
                address: referredPatientLocation.trim(),
              ),
            );
          }
          notifyListeners();
        } catch (_) {}
      }

      return res;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Doctor Accepts Referral
  Future<bool> acceptPatientReferralByDoctor(String referralId, {String? confirmedTimeSlot}) async {
    try {
      final res = await ApiService().acceptPatientReferral(referralId, confirmedTimeSlot: confirmedTimeSlot);
      if (res['success'] == true) {
        final idx = _doctorReceivedPatientReferrals.indexWhere((r) => r.id == referralId);
        if (idx != -1) {
          final old = _doctorReceivedPatientReferrals[idx];
          _doctorReceivedPatientReferrals[idx] = PatientReferral(
            id: old.id,
            referrerPatientId: old.referrerPatientId,
            referrerPatientName: old.referrerPatientName,
            referrerPatientPhone: old.referrerPatientPhone,
            referrerPatientEmail: old.referrerPatientEmail,
            referredPatientId: old.referredPatientId,
            referredPatientName: old.referredPatientName,
            referredPatientMobile: old.referredPatientMobile,
            referredPatientAge: old.referredPatientAge,
            referredPatientGender: old.referredPatientGender,
            referredPatientCity: old.referredPatientCity,
            referredPatientPincode: old.referredPatientPincode,
            referredPatientLocation: old.referredPatientLocation,
            requiredSpecialist: old.requiredSpecialist,
            clinicalComplaint: old.clinicalComplaint,
            doctorId: old.doctorId,
            doctorName: old.doctorName,
            doctorSpecialty: old.doctorSpecialty,
            doctorClinicName: old.doctorClinicName,
            doctorCity: old.doctorCity,
            doctorPincode: old.doctorPincode,
            doctorLocation: old.doctorLocation,
            doctorLanguages: old.doctorLanguages,
            status: 'Accepted',
            whatsappStatus: 'Sent',
            referralDate: old.referralDate,
            createdAt: old.createdAt,
            updatedAt: DateTime.now(),
          );
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error accepting referral: $e');
    }
    return false;
  }

  /// Doctor Rejects Referral
  Future<bool> rejectPatientReferralByDoctor(String referralId, {String? rejectionReason}) async {
    try {
      final res = await ApiService().rejectPatientReferral(referralId, rejectionReason: rejectionReason);
      if (res['success'] == true) {
        final idx = _doctorReceivedPatientReferrals.indexWhere((r) => r.id == referralId);
        if (idx != -1) {
          final old = _doctorReceivedPatientReferrals[idx];
          _doctorReceivedPatientReferrals[idx] = PatientReferral(
            id: old.id,
            referrerPatientId: old.referrerPatientId,
            referrerPatientName: old.referrerPatientName,
            referrerPatientPhone: old.referrerPatientPhone,
            referrerPatientEmail: old.referrerPatientEmail,
            referredPatientId: old.referredPatientId,
            referredPatientName: old.referredPatientName,
            referredPatientMobile: old.referredPatientMobile,
            referredPatientAge: old.referredPatientAge,
            referredPatientGender: old.referredPatientGender,
            referredPatientCity: old.referredPatientCity,
            referredPatientPincode: old.referredPatientPincode,
            referredPatientLocation: old.referredPatientLocation,
            requiredSpecialist: old.requiredSpecialist,
            clinicalComplaint: old.clinicalComplaint,
            doctorId: old.doctorId,
            doctorName: old.doctorName,
            doctorSpecialty: old.doctorSpecialty,
            doctorClinicName: old.doctorClinicName,
            doctorCity: old.doctorCity,
            doctorPincode: old.doctorPincode,
            doctorLocation: old.doctorLocation,
            doctorLanguages: old.doctorLanguages,
            status: 'Rejected',
            rejectionReason: rejectionReason,
            whatsappStatus: 'Sent',
            referralDate: old.referralDate,
            createdAt: old.createdAt,
            updatedAt: DateTime.now(),
          );
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error rejecting referral: $e');
    }
    return false;
  }

  /// Delete a Patient Referral
  Future<bool> deletePatientReferral(String referralId) async {
    try {
      _myCreatedPatientReferrals.removeWhere((r) => r.id == referralId);
      _doctorReceivedPatientReferrals.removeWhere((r) => r.id == referralId);
      _receivedForMePatientReferrals.removeWhere((r) => r.id == referralId);
      _adminPatientReferrals.removeWhere((r) => r.id == referralId);
      _myReferrals.removeWhere((r) => r.id == referralId);
      _adminReferrals.removeWhere((r) => r.id == referralId);
      notifyListeners();

      final res = await ApiService().deletePatientReferral(referralId);
      return res['success'] == true;
    } catch (e) {
      debugPrint('Error deleting patient referral: $e');
      return false;
    }
  }

  Future<void> syncAdminReferralsFromApi() async {
    try {
      final res = await ApiService().fetchAllReferralsAdmin();
      if (res['success'] == true && res['referrals'] is List) {
        final list = res['referrals'] as List;
        _adminPatientReferrals = list
            .map((r) => PatientReferral.fromJson(Map<String, dynamic>.from(r)))
            .toList();
        _adminReferrals = list
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

  /// Sync In-App Notifications from DB & synthesize dynamic consultation/referral alerts
  Future<void> syncNotificationsFromApi({String? role, String? userId}) async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final effectiveRole = role ?? (currentDoctor != null ? 'Dentist' : 'Patient');
      final effectiveUserId = userId ?? (effectiveRole == 'Dentist' ? (currentDoctor?.id ?? authUser?.id) : (currentPatient.id.isNotEmpty ? currentPatient.id : authUser?.id));

      final rawList = await ApiService().fetchNotifications(
        role: effectiveRole,
        userId: effectiveUserId,
      );

      final Map<String, AppNotificationModel> notifMap = {};

      // 1. Add existing local in-app notifications
      for (final n in _appNotifications) {
        if (n.id.isNotEmpty) notifMap[n.id] = n;
      }

      // 2. Add API notifications from DB
      for (final item in rawList) {
        try {
          final id = item['id']?.toString() ?? 'NOTIF-${DateTime.now().millisecondsSinceEpoch}';
          final rRole = item['recipient_role']?.toString() ?? effectiveRole;
          final rId = item['recipient_id']?.toString() ?? item['user_id']?.toString() ?? '';
          final title = item['title']?.toString() ?? 'GS HEALTH Notification';
          final message = item['message']?.toString() ?? '';
          final isRead = item['read'] == true || item['is_read'] == true;
          final ts = item['created_at'] != null ? (DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now()) : DateTime.now();

          notifMap[id] = AppNotificationModel(
            id: id,
            recipientRole: rRole,
            recipientId: rId,
            title: title,
            message: message,
            timestamp: ts,
            isRead: isRead,
          );
        } catch (_) {}
      }

      // 3. Automatically synthesize in-app notifications for direct referrals & assigned consultations
      if (effectiveRole == 'Dentist') {
        for (final ref in _doctorReceivedPatientReferrals) {
          final notifKey = 'REF-NOTIF-${ref.id}';
          if (!notifMap.containsKey(notifKey)) {
            notifMap[notifKey] = AppNotificationModel(
              id: notifKey,
              recipientRole: 'Dentist',
              recipientId: effectiveUserId ?? '',
              title: ref.status == 'Accepted' ? '✅ Consultation Confirmed' : '👥 New Patient Referral',
              message: 'Patient ${ref.referredPatientName} (${ref.referredPatientMobile}) referred for ${ref.requiredSpecialist}.',
              timestamp: ref.createdAt,
              isRead: ref.status == 'Accepted',
            );
          }
        }

        for (final req in _dentistAssignedRequests) {
          final notifKey = 'REQ-NOTIF-${req.id}';
          if (!notifMap.containsKey(notifKey)) {
            notifMap[notifKey] = AppNotificationModel(
              id: notifKey,
              recipientRole: 'Dentist',
              recipientId: effectiveUserId ?? '',
              title: (req.status == 'Accepted' || req.status == 'Confirmed') ? '✅ Active Consultation' : '🩺 New Patient Assigned',
              message: '${req.patientName} assigned for ${req.problemCategory}. Severity: ${req.severity}.',
              timestamp: req.submittedAt,
              isRead: req.status == 'Accepted' || req.status == 'Confirmed',
            );
          }
        }
      }

      _appNotifications.clear();
      final sortedList = notifMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _appNotifications.addAll(sortedList);
      notifyListeners();
    } catch (e) {
      debugPrint('Error in syncNotificationsFromApi: $e');
    }
  }

  /// Mark single notification as read
  Future<void> markNotificationRead(String notifId) async {
    final idx = _appNotifications.indexWhere((n) => n.id == notifId);
    if (idx != -1) {
      _appNotifications[idx].isRead = true;
      notifyListeners();
      _saveToStorage();
      await ApiService().markNotificationAsRead(notifId);
    }
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsRead(String role) async {
    for (final n in _appNotifications) {
      if (n.recipientRole == role || n.recipientRole == 'ALL') {
        n.isRead = true;
        ApiService().markNotificationAsRead(n.id);
      }
    }
    notifyListeners();
    _saveToStorage();
  }

  // ─────────────────────────────────────────────
  // DOCTOR AVAILABILITY STATE & API INTEGRATION
  // ─────────────────────────────────────────────
  final Map<String, DoctorAvailabilityModel> _availabilityCache = {};

  DoctorAvailabilityModel? getCachedAvailability(String doctorId, String dateStr) {
    return _availabilityCache['${doctorId}_$dateStr'];
  }

  /// Helper: Generate time slots given start, end, duration and break period
  List<String> generateTimeSlots({
    String startTime = '09:00 AM',
    String endTime = '05:00 PM',
    int durationMinutes = 30,
    String? breakStartTime,
    String? breakEndTime,
  }) {
    int timeToMinutes(String timeStr) {
      final parts = timeStr.trim().split(' ');
      if (parts.length < 2) return 0;
      final timeParts = parts[0].split(':');
      int hours = int.tryParse(timeParts[0]) ?? 0;
      final minutes = int.tryParse(timeParts[1]) ?? 0;
      final period = parts[1].toUpperCase();
      if (period == 'PM' && hours < 12) hours += 12;
      if (period == 'AM' && hours == 12) hours = 0;
      return hours * 60 + minutes;
    }

    String minutesToTime(int totalMinutes) {
      int hours = (totalMinutes ~/ 60) % 24;
      final minutes = totalMinutes % 60;
      final period = hours >= 12 ? 'PM' : 'AM';
      if (hours > 12) hours -= 12;
      if (hours == 0) hours = 12;
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')} $period';
    }

    final start = timeToMinutes(startTime);
    final end = timeToMinutes(endTime);
    final duration = durationMinutes < 15 ? 30 : durationMinutes;
    if (start >= end) return [];

    final hasBreak = breakStartTime != null && breakEndTime != null && breakStartTime.trim().isNotEmpty && breakEndTime.trim().isNotEmpty;
    final breakStart = hasBreak ? timeToMinutes(breakStartTime) : -1;
    final breakEnd = hasBreak ? timeToMinutes(breakEndTime) : -1;

    final slots = <String>[];
    int current = start;
    while (current + duration <= end) {
      final slotEnd = current + duration;
      final overlapsBreak = hasBreak && (
          (current >= breakStart && current < breakEnd) ||
          (slotEnd > breakStart && slotEnd <= breakEnd) ||
          (current <= breakStart && slotEnd >= breakEnd)
      );

      if (!overlapsBreak) {
        slots.add(minutesToTime(current));
      }
      current += duration;
    }
    return slots;
  }

  /// Fetch all configured availability records for a doctor across dates
  Future<List<DoctorAvailabilityModel>> getDoctorConfiguredAvailabilities(String doctorId) async {
    try {
      final res = await _api.fetchDoctorAvailability(dentistId: doctorId);
      if (res['success'] == true && res['availabilities'] is List) {
        final list = <DoctorAvailabilityModel>[];
        for (final item in (res['availabilities'] as List)) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final rawSlots = map['slots'] ?? map['allSlots'] ?? [];
            final allSlots = rawSlots is List
                ? rawSlots.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
                : <String>[];
            final isBlocked = map['is_blocked'] == true || map['isBlocked'] == true;
            list.add(
              DoctorAvailabilityModel(
                id: (map['id'] ?? '').toString(),
                dentistId: (map['dentist_id'] ?? map['dentistId'] ?? doctorId).toString(),
                date: (map['date'] ?? '').toString().split('T').first,
                dayOfWeek: (map['day_of_week'] ?? map['dayOfWeek'] ?? '').toString(),
                startTime: (map['start_time'] ?? map['startTime'] ?? '09:00 AM').toString(),
                endTime: (map['end_time'] ?? map['endTime'] ?? '05:00 PM').toString(),
                slotDurationMinutes: int.tryParse((map['slot_duration_minutes'] ?? map['slotDurationMinutes'] ?? '30').toString()) ?? 30,
                allSlots: allSlots,
                bookedSlots: const [],
                availableSlots: isBlocked ? const [] : allSlots,
                isBlocked: isBlocked,
                blockedReason: (map['blocked_reason'] ?? map['blockedReason'])?.toString(),
              ),
            );
          }
        }
        return list;
      }
    } catch (e) {
      debugPrint('getDoctorConfiguredAvailabilities notice: $e');
    }
    return [];
  }

  /// Get Doctor Availability for a specific date (reads backend, fallback to doctor default slots)
  Future<DoctorAvailabilityModel> getDoctorAvailability(String doctorId, DateTime date) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final cacheKey = '${doctorId}_$dateStr';

    final doctor = _allDoctors.firstWhere(
      (d) => d.id == doctorId || (d.userId.isNotEmpty && d.userId == doctorId),
      orElse: () => DoctorModel(
        id: doctorId,
        name: '',
        specialty: '',
        qualification: '',
        experienceYears: 0,
        rating: 0,
        reviewCount: 0,
        clinicName: '',
        phone: '',
        email: '',
        status: '',
        nextAvailableSlots: [],
        consultationFee: '',
      ),
    );

    // Cross-reference existing appointments in memory for this doctor and date
    final localBooked = <String>[];
    for (final req in _requests) {
      final matchesDoc = req.assignedDoctorId == doctorId ||
          (doctor.id.isNotEmpty && req.assignedDoctorId == doctor.id) ||
          (doctor.userId.isNotEmpty && req.assignedDoctorId == doctor.userId) ||
          (doctor.name.isNotEmpty && req.assignedDoctorName == doctor.name);
      if (matchesDoc) {
        final s = req.status.toUpperCase();
        if (s != 'CANCELLED' && s != 'REJECTED') {
          final rDate = req.confirmedDate?.split('T').first ?? req.submittedAt.toIso8601String().split('T').first;
          if (rDate == dateStr) {
            final slot = req.confirmedTimeSlot?.trim() ?? '';
            if (slot.isNotEmpty && !localBooked.any((b) => b.toLowerCase() == slot.toLowerCase())) {
              localBooked.add(slot);
            }
          }
        }
      }
    }

    DoctorAvailabilityModel? apiModel;
    try {
      final res = await _api.fetchDoctorAvailability(dentistId: doctorId, date: dateStr);
      if (res['success'] == true && res['availability'] != null) {
        apiModel = DoctorAvailabilityModel.fromJson(Map<String, dynamic>.from(res['availability']));
        // Merge local booked slots with API booked slots
        final mergedBooked = <String>[...apiModel.bookedSlots];
        for (final lb in localBooked) {
          if (!mergedBooked.any((b) => b.toLowerCase() == lb.toLowerCase())) {
            mergedBooked.add(lb);
          }
        }
        if (apiModel.isBlocked || apiModel.allSlots.isNotEmpty) {
          final available = apiModel.isBlocked
              ? <String>[]
              : apiModel.allSlots.where((s) => !mergedBooked.any((b) => b.toLowerCase() == s.toLowerCase())).toList();
          final resolved = apiModel.copyWith(
            bookedSlots: mergedBooked,
            availableSlots: available,
          );
          _availabilityCache[cacheKey] = resolved;
          notifyListeners();
          return resolved;
        }
        apiModel = apiModel.copyWith(bookedSlots: mergedBooked);
      }
    } catch (e) {
      debugPrint('getDoctorAvailability api fetch notice: $e');
    }

    // Check if we have a cached model with configured slots or blocked state
    if (_availabilityCache.containsKey(cacheKey)) {
      final cached = _availabilityCache[cacheKey]!;
      if (cached.isBlocked || cached.allSlots.isNotEmpty) {
        final mergedBooked = <String>[...cached.bookedSlots];
        if (apiModel != null) {
          for (final ab in apiModel.bookedSlots) {
            if (!mergedBooked.any((b) => b.toLowerCase() == ab.toLowerCase())) {
              mergedBooked.add(ab);
            }
          }
        }
        for (final lb in localBooked) {
          if (!mergedBooked.any((b) => b.toLowerCase() == lb.toLowerCase())) {
            mergedBooked.add(lb);
          }
        }
        final available = cached.isBlocked
            ? <String>[]
            : cached.allSlots.where((s) => !mergedBooked.any((b) => b.toLowerCase() == s.toLowerCase())).toList();
        final updated = cached.copyWith(bookedSlots: mergedBooked, availableSlots: available);
        _availabilityCache[cacheKey] = updated;
        return updated;
      }
    }

    final isDoctorOnLeave = doctor.status.trim().toLowerCase() == 'on leave' ||
        doctor.status.trim().toLowerCase() == 'unavailable';
    if (isDoctorOnLeave) {
      final blockedModel = DoctorAvailabilityModel(
        dentistId: doctorId,
        date: dateStr,
        startTime: '09:00 AM',
        endTime: '05:00 PM',
        slotDurationMinutes: 30,
        allSlots: const [],
        bookedSlots: localBooked,
        availableSlots: const [],
        isBlocked: true,
        blockedReason: 'Doctor is currently on leave',
      );
      _availabilityCache[cacheKey] = blockedModel;
      return blockedModel;
    }

    // Use doctor's valid time slots or standard working hours minus booked appointments
    final timePattern = RegExp(r'^\d{1,2}:\d{2}\s*(AM|PM)$', caseSensitive: false);
    final validCustomSlots = doctor.nextAvailableSlots
        .map((s) => s.trim())
        .where((s) => timePattern.hasMatch(s))
        .toList();

    final List<String> defaultSlots = validCustomSlots.isNotEmpty
        ? validCustomSlots
        : generateTimeSlots(
            startTime: apiModel?.startTime ?? '09:00 AM',
            endTime: apiModel?.endTime ?? '05:00 PM',
            durationMinutes: apiModel?.slotDurationMinutes ?? 30,
          );

    final booked = <String>[
      if (apiModel != null) ...apiModel.bookedSlots,
    ];
    for (final lb in localBooked) {
      if (!booked.any((b) => b.toLowerCase() == lb.toLowerCase())) {
        booked.add(lb);
      }
    }

    final available = defaultSlots.where((s) => !booked.any((b) => b.toLowerCase() == s.toLowerCase())).toList();

    final fallbackModel = DoctorAvailabilityModel(
      dentistId: doctorId,
      date: dateStr,
      startTime: apiModel?.startTime ?? '09:00 AM',
      endTime: apiModel?.endTime ?? '05:00 PM',
      slotDurationMinutes: apiModel?.slotDurationMinutes ?? 30,
      allSlots: defaultSlots,
      bookedSlots: booked,
      availableSlots: available,
      isBlocked: false,
    );

    _availabilityCache[cacheKey] = fallbackModel;
    return fallbackModel;
  }

  /// Admin, Clinic Admin or Doctor publishes/saves availability slots
  Future<bool> publishDoctorAvailability({
    required String doctorId,
    required DateTime date,
    required List<String> slots,
    List<DateTime>? batchDates,
    String startTime = '09:00 AM',
    String endTime = '05:00 PM',
    int slotDurationMinutes = 30,
    String? breakStartTime,
    String? breakEndTime,
    List<String>? workingDays,
    bool isBlocked = false,
    String? blockedReason,
    String dayOfWeek = '',
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final formattedBatchDates = batchDates?.map((d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
    ).toList();

    final res = await _api.saveDoctorAvailability(
      dentistId: doctorId,
      date: dateStr,
      dates: formattedBatchDates,
      slots: slots,
      startTime: startTime,
      endTime: endTime,
      slotDurationMinutes: slotDurationMinutes,
      breakStartTime: breakStartTime,
      breakEndTime: breakEndTime,
      workingDays: workingDays,
      isBlocked: isBlocked,
      blockedReason: blockedReason,
      dayOfWeek: dayOfWeek,
    );

    if (res['success'] == true) {
      // Invalidate and refresh cached model for primary date and batch dates
      _availabilityCache.remove('${doctorId}_$dateStr');
      await getDoctorAvailability(doctorId, date);
      if (batchDates != null) {
        for (final bDate in batchDates) {
          final bDateStr = '${bDate.year.toString().padLeft(4, '0')}-${bDate.month.toString().padLeft(2, '0')}-${bDate.day.toString().padLeft(2, '0')}';
          _availabilityCache.remove('${doctorId}_$bDateStr');
        }
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Block a doctor date
  Future<bool> blockDoctorDate({
    required String doctorId,
    required DateTime date,
    String reason = 'Doctor on Leave / Clinic Closed',
  }) async {
    final dateStr = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final cacheKey = '${doctorId}_$dateStr';

    final res = await _api.blockDoctorDate(
      dentistId: doctorId,
      date: dateStr,
      reason: reason,
    );

    if (res['success'] == true) {
      final existing = _availabilityCache[cacheKey];
      if (existing != null) {
        _availabilityCache[cacheKey] = existing.copyWith(isBlocked: true, blockedReason: reason, availableSlots: []);
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  // =========================================================================
  // MULTI-SPECIALTY HEALTHCARE PLATFORM MANAGEMENT (Specialties, Profiles, Departments)
  // =========================================================================

  List<MedicalSpecialtyModel> _specialties = List.from(MedicalSpecialtyModel.defaultSpecialties);

  /// All registered medical specialties (active and inactive)
  List<MedicalSpecialtyModel> get specialties => List.unmodifiable(_specialties);

  /// Active medical specialties available for Patient discovery and Doctor registration
  List<MedicalSpecialtyModel> get activeSpecialties =>
      List.unmodifiable(_specialties.where((s) => s.isActive).toList());

  /// Active medical specialty names
  List<String> get activeSpecialtyNames =>
      _specialties.where((s) => s.isActive).map((s) => s.name).toList();

  /// Clinic multi-specialty departments enabled for the clinic workspace
  final List<String> _clinicDepartments = [
    'General Medicine',
    'Cardiology',
    'Dermatology',
    'Neurology',
    'Orthopedics',
    'Pediatrics',
    'Gynecology',
    'ENT',
    'Ophthalmology',
    'Dentistry',
  ];

  List<String> get clinicDepartments => List.unmodifiable(_clinicDepartments);

  Future<void> syncSpecialtiesFromApi() async {
    try {
      final rows = await ApiService().fetchMedicalSpecialties(activeOnly: false);
      if (rows.isNotEmpty) {
        final fetched = rows
            .map((r) => MedicalSpecialtyModel.fromJson(r))
            .where((s) => s.name.isNotEmpty)
            .toList();
        if (fetched.isNotEmpty) {
          // Merge with any default specialties not yet in DB so all 16 core specialties remain available
          final byCode = <String, MedicalSpecialtyModel>{};
          for (final def in MedicalSpecialtyModel.defaultSpecialties) {
            byCode[def.code.toUpperCase()] = def;
          }
          for (final item in fetched) {
            final key = item.code.isNotEmpty
                ? item.code.toUpperCase()
                : item.name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
            byCode[key] = item;
          }
          final merged = byCode.values.toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          _specialties = merged;
          _saveToStorage();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Sync specialties notice: $e');
    }
  }

  Future<MedicalSpecialtyModel> addMedicalSpecialty({
    required String name,
    String? code,
    String? department,
    String? description,
    String? defaultQualifications,
    List<String>? consultationTypes,
    List<String>? subSpecialties,
    String icon = 'medical_services',
  }) async {
    final cleanName = name.trim();
    final cleanCode = (code != null && code.trim().isNotEmpty)
        ? code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        : cleanName.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    final newSpec = MedicalSpecialtyModel(
      id: 'spec-${cleanCode.toLowerCase()}',
      code: cleanCode,
      name: cleanName,
      department: (department != null && department.trim().isNotEmpty)
          ? department.trim()
          : '$cleanName Department',
      description: (description != null && description.trim().isNotEmpty)
          ? description.trim()
          : 'Specialized consultations, diagnostics, and clinical care in $cleanName.',
      iconName: icon,
      defaultQualifications: (defaultQualifications != null && defaultQualifications.trim().isNotEmpty)
          ? defaultQualifications.trim()
          : 'MBBS, MD',
      consultationTypes: (consultationTypes != null && consultationTypes.isNotEmpty)
          ? consultationTypes
          : ['General Consultation', 'Specialist Evaluation', 'Follow-up Visit'],
      subSpecialties: subSpecialties ?? const [],
      isActive: true,
      displayOrder: _specialties.length + 1,
    );

    final existingIdx = _specialties.indexWhere(
      (s) => s.code.toLowerCase() == cleanCode.toLowerCase() || s.name.toLowerCase() == cleanName.toLowerCase(),
    );
    if (existingIdx != -1) {
      _specialties[existingIdx] = newSpec;
    } else {
      _specialties.add(newSpec);
    }
    _saveToStorage();
    notifyListeners();

    await ApiService().createMedicalSpecialty(newSpec.toJson());
    return newSpec;
  }

  Future<void> updateMedicalSpecialty(
    String idOrCode, {
    String? name,
    String? department,
    String? description,
    String? defaultQualifications,
    List<String>? consultationTypes,
    List<String>? subSpecialties,
    bool? isActive,
  }) async {
    final idx = _specialties.indexWhere(
      (s) => s.id == idOrCode || s.code.toLowerCase() == idOrCode.toLowerCase() || s.name.toLowerCase() == idOrCode.toLowerCase(),
    );
    if (idx == -1) return;

    final updated = _specialties[idx].copyWith(
      name: name,
      department: department,
      description: description,
      defaultQualifications: defaultQualifications,
      consultationTypes: consultationTypes,
      subSpecialties: subSpecialties,
      isActive: isActive,
    );
    _specialties[idx] = updated;
    _saveToStorage();
    notifyListeners();

    await ApiService().updateMedicalSpecialty(updated.id, updated.toJson());
  }

  Future<void> toggleMedicalSpecialtyStatus(String idOrCode, bool isActive) async {
    final idx = _specialties.indexWhere(
      (s) => s.id == idOrCode || s.code.toLowerCase() == idOrCode.toLowerCase() || s.name.toLowerCase() == idOrCode.toLowerCase(),
    );
    if (idx == -1) return;
    _specialties[idx] = _specialties[idx].copyWith(isActive: isActive);
    _saveToStorage();
    notifyListeners();
    await ApiService().toggleMedicalSpecialtyStatus(_specialties[idx].id, isActive);
  }

  Future<void> addClinicDepartment(String departmentName, {String? clinicId}) async {
    final clean = departmentName.trim();
    if (clean.isEmpty) return;
    if (!_clinicDepartments.any((d) => d.toLowerCase() == clean.toLowerCase())) {
      _clinicDepartments.add(clean);
      _saveToStorage();
      notifyListeners();
      if (clinicId != null && clinicId.isNotEmpty) {
        await ApiService().updateClinicDepartmentsApi(clinicId, _clinicDepartments);
      }
    }
  }

  Future<void> removeClinicDepartment(String departmentName, {String? clinicId}) async {
    _clinicDepartments.removeWhere((d) => d.toLowerCase() == departmentName.trim().toLowerCase());
    _saveToStorage();
    notifyListeners();
    if (clinicId != null && clinicId.isNotEmpty) {
      await ApiService().updateClinicDepartmentsApi(clinicId, _clinicDepartments);
    }
  }

  Future<void> updateDoctorProfessionalProfile({
    required String doctorId,
    String? name,
    String? specialty,
    String? qualification,
    int? experienceYears,
    String? clinicName,
    String? consultationFee,
    String? licenseNumber,
    String? status,
    String? verificationStatus,
    String? bio,
    String? city,
    String? pincode,
  }) async {
    int idx = _allDoctors.indexWhere((d) => d.id == doctorId || (d.userId.isNotEmpty && d.userId == doctorId));
    DoctorModel? baseDoc = idx != -1 ? _allDoctors[idx] : currentDoctor;
    if (baseDoc == null) return;

    final updatedDoc = DoctorModel(
      id: baseDoc.id,
      userId: baseDoc.userId,
      name: name ?? baseDoc.name,
      specialty: specialty ?? baseDoc.specialty,
      qualification: qualification ?? baseDoc.qualification,
      experienceYears: experienceYears ?? baseDoc.experienceYears,
      rating: baseDoc.rating,
      reviewCount: baseDoc.reviewCount,
      clinicName: clinicName ?? baseDoc.clinicName,
      phone: baseDoc.phone,
      email: baseDoc.email,
      status: status ?? baseDoc.status,
      verificationStatus: verificationStatus ?? baseDoc.verificationStatus,
      nextAvailableSlots: baseDoc.nextAvailableSlots,
      consultationFee: consultationFee ?? baseDoc.consultationFee,
      licenseNumber: licenseNumber ?? baseDoc.licenseNumber,
      photoBytes: baseDoc.photoBytes,
      clinicAddress: baseDoc.clinicAddress,
      pincode: pincode ?? baseDoc.pincode,
      city: city ?? baseDoc.city,
      state: baseDoc.state,
      bio: bio ?? baseDoc.bio,
      languages: baseDoc.languages,
      latitude: baseDoc.latitude,
      longitude: baseDoc.longitude,
      procedureFees: baseDoc.procedureFees,
    );

    if (idx != -1) {
      _allDoctors[idx] = updatedDoc;
    } else {
      _allDoctors.insert(0, updatedDoc);
    }

    if (currentDoctor != null &&
        (currentDoctor!.id == doctorId ||
            currentDoctor!.userId == doctorId ||
            currentDoctor!.email.toLowerCase() == updatedDoc.email.toLowerCase())) {
      currentDoctor = updatedDoc;
    }

    _saveToStorage();
    notifyListeners();

    await ApiService().updateDoctorProfileApi(doctorId, {
      if (name != null) 'name': name,
      if (specialty != null) 'specialty': specialty,
      if (qualification != null) 'qualification': qualification,
      if (experienceYears != null) 'experienceYears': experienceYears,
      if (clinicName != null) 'clinicName': clinicName,
      if (consultationFee != null) 'consultationFee': consultationFee,
      if (licenseNumber != null) 'licenseNumber': licenseNumber,
      if (status != null) 'status': status,
      if (verificationStatus != null) 'verificationStatus': verificationStatus,
      if (bio != null) 'bio': bio,
      if (city != null) 'city': city,
      if (pincode != null) 'pincode': pincode,
    });
  }

  /// Compute specialty-based analytics report across all active & registered specialties
  List<Map<String, dynamic>> getSpecialtyAnalyticsBreakdown() {
    return _specialties.map<Map<String, dynamic>>((spec) {
      final matchingDocs = _allDoctors
          .where((d) => MedicalSpecialtyModel.matchesSpecialtyFilter(d.specialty, spec.name, specialties: _specialties))
          .toList();
      final verifiedDocs = matchingDocs.where((d) => d.verificationStatus.toUpperCase() == 'VERIFIED').length;
      final docIds = matchingDocs.map((d) => d.id).toSet();
      final docNames = matchingDocs.map((d) => d.name.toLowerCase()).toSet();

      final matchingRequests = _requests.where((r) {
        if (r.assignedDoctorSpecialty != null &&
            MedicalSpecialtyModel.matchesSpecialtyFilter(r.assignedDoctorSpecialty!, spec.name, specialties: _specialties)) {
          return true;
        }
        if (r.assignedDoctorId != null && docIds.contains(r.assignedDoctorId)) return true;
        if (r.assignedDoctorName != null && docNames.contains(r.assignedDoctorName!.toLowerCase())) return true;
        return MedicalSpecialtyModel.matchesSpecialtyFilter(r.problemCategory, spec.name, specialties: _specialties);
      }).toList();

      final confirmedAppointments = matchingRequests
          .where((r) => r.status.toUpperCase() == 'CONFIRMED' || r.confirmedTimeSlot != null)
          .length;

      return <String, dynamic>{
        'id': spec.id,
        'code': spec.code,
        'name': spec.name,
        'department': spec.department,
        'defaultQualifications': spec.defaultQualifications,
        'isActive': spec.isActive,
        'totalDoctors': matchingDocs.length,
        'verifiedDoctors': verifiedDocs,
        'consultations': matchingRequests.length,
        'totalConsultations': matchingRequests.length,
        'appointments': confirmedAppointments,
        'confirmedAppointments': confirmedAppointments,
      };
    }).toList();
  }

  // =========================================================================
  // CLINIC DOCTORS & MULTI-SPECIALTY CLINIC MANAGEMENT
  // =========================================================================

  /// Retrieve all doctors attached or associated with a specific clinic
  List<DoctorModel> getClinicDoctors(String clinicName) {
    final clean = clinicName.trim().toLowerCase();
    if (clean.isEmpty) return _allDoctors;
    final matches = _allDoctors.where((d) {
      final docClinic = d.clinicName.trim().toLowerCase();
      if (docClinic == clean) return true;
      if (docClinic.isNotEmpty && (clean.contains(docClinic) || docClinic.contains(clean))) return true;
      return false;
    }).toList();

    // Fallback if demo clinic has no specific matches so the UI remains fully functional
    if (matches.isEmpty && (clean.contains('gs health') || clean.contains('partner clinic') || clean.contains('default'))) {
      return _allDoctors;
    }
    return matches;
  }

  /// Check if a doctor already exists in GS HEALTH by phone, email, or license
  DoctorModel? findExistingDoctor({String? phone, String? email, String? licenseNumber}) {
    final cleanPhone = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final cleanEmail = (email ?? '').trim().toLowerCase();
    final cleanLicense = (licenseNumber ?? '').trim().toLowerCase();

    for (final doc in _allDoctors) {
      if (cleanEmail.isNotEmpty && doc.email.trim().toLowerCase() == cleanEmail) {
        return doc;
      }
      final docPhone = doc.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.length >= 10 && docPhone.length >= 10 && docPhone.endsWith(cleanPhone.substring(cleanPhone.length - 10))) {
        return doc;
      }
      if (cleanLicense.isNotEmpty && doc.licenseNumber.trim().toLowerCase() == cleanLicense) {
        return doc;
      }
    }
    return null;
  }

  /// Associate an existing doctor with a clinic without creating a duplicate account
  Future<bool> associateDoctorWithClinic({
    required String doctorId,
    required String clinicName,
    String? specialty,
    String? consultationFee,
    List<String>? availableDays,
    List<String>? availableSlots,
  }) async {
    final idx = _allDoctors.indexWhere((d) => d.id == doctorId || d.userId == doctorId);
    if (idx != -1) {
      final base = _allDoctors[idx];
      final updatedSlots = (availableSlots != null && availableSlots.isNotEmpty)
          ? availableSlots
          : base.nextAvailableSlots;
      final updated = DoctorModel(
        id: base.id,
        userId: base.userId,
        name: base.name,
        specialty: (specialty != null && specialty.trim().isNotEmpty) ? specialty.trim() : base.specialty,
        qualification: base.qualification,
        experienceYears: base.experienceYears,
        rating: base.rating,
        reviewCount: base.reviewCount,
        clinicName: clinicName.trim(),
        phone: base.phone,
        email: base.email,
        status: 'Available',
        verificationStatus: base.verificationStatus,
        nextAvailableSlots: updatedSlots,
        consultationFee: (consultationFee != null && consultationFee.trim().isNotEmpty)
            ? consultationFee.trim()
            : base.consultationFee,
        licenseNumber: base.licenseNumber,
        photoBytes: base.photoBytes,
        clinicAddress: base.clinicAddress,
        city: base.city,
        pincode: base.pincode,
        state: base.state,
        bio: base.bio,
        languages: base.languages,
        latitude: base.latitude,
        longitude: base.longitude,
        procedureFees: base.procedureFees,
      );
      _allDoctors[idx] = updated;
      _saveToStorage();
      notifyListeners();

      await ApiService().associateClinicDoctorApi(
        clinicId: 'default',
        doctorId: doctorId,
        clinicName: clinicName,
        specialty: specialty,
        consultationFee: consultationFee,
        availableDays: availableDays,
        availableSlots: availableSlots,
      );
      return true;
    }
    return false;
  }

  /// Remove a doctor from a clinic without deleting their global account or patient records
  Future<bool> removeDoctorFromClinic({
    required String doctorId,
    required String clinicName,
  }) async {
    final idx = _allDoctors.indexWhere((d) => d.id == doctorId || d.userId == doctorId);
    if (idx != -1) {
      final base = _allDoctors[idx];
      final updated = DoctorModel(
        id: base.id,
        userId: base.userId,
        name: base.name,
        specialty: base.specialty,
        qualification: base.qualification,
        experienceYears: base.experienceYears,
        rating: base.rating,
        reviewCount: base.reviewCount,
        clinicName: 'Independent Practice',
        phone: base.phone,
        email: base.email,
        status: base.status,
        verificationStatus: base.verificationStatus,
        nextAvailableSlots: base.nextAvailableSlots,
        consultationFee: base.consultationFee,
        licenseNumber: base.licenseNumber,
        photoBytes: base.photoBytes,
        clinicAddress: base.clinicAddress,
        city: base.city,
        pincode: base.pincode,
        state: base.state,
        bio: base.bio,
        languages: base.languages,
        latitude: base.latitude,
        longitude: base.longitude,
        procedureFees: base.procedureFees,
      );
      _allDoctors[idx] = updated;
      _saveToStorage();
      notifyListeners();

      await ApiService().removeDoctorFromClinicApi(
        clinicId: 'default',
        doctorId: doctorId,
      );
      return true;
    }
    return false;
  }
}


