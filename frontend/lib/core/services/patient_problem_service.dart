import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';
import 'session_service.dart';
import 'supabase_service.dart';
import '../constants/booking_rules_config.dart';
import '../constants/patient_profile_requirements.dart';
import '../models/referral_model.dart';
import '../models/doctor_availability.dart';
import '../models/medical_specialty_model.dart';
import '../models/specialty_clinical_config.dart';
import '../utils/clinic_directions_helper.dart';

/// Model representing a Doctor/Dentist registered in DentaGuru platform
class DoctorModel {
  final String id;
  final String userId;
  final String clinicId;
  final String name;
  final String specialty;
  final String department;
  final String qualification;
  final int experienceYears;
  final double rating;
  final int reviewCount;
  final String clinicName;
  final String phone;
  final String email;
  final String status; // 'Online', 'Offline', 'Available', 'Busy', 'Unavailable'
  final String onlineStatus; // Optional explicit online presence ('Online', 'Offline', 'Busy')
  final String verificationStatus; // 'VERIFIED', 'PENDING_VERIFICATION', 'REJECTED', 'SUSPENDED'
  final List<String> nextAvailableSlots;
  final String consultationFee;
  final String licenseNumber;
  final Uint8List? photoBytes;
  final String? profileImageUrl;
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
    this.clinicId = '',
    required this.name,
    required this.specialty,
    this.department = '',
    required this.qualification,
    required this.experienceYears,
    required this.rating,
    required this.reviewCount,
    required this.clinicName,
    required this.phone,
    required this.email,
    required this.status,
    this.onlineStatus = '',
    this.verificationStatus = 'VERIFIED',
    required this.nextAvailableSlots,
    required this.consultationFee,
    this.licenseNumber = 'MED-LIC-REG',
    this.photoBytes,
    this.profileImageUrl,
    this.clinicAddress = '',
    this.pincode = '',
    this.city = '',
    this.state = '',
    this.bio = '',
    this.languages = const ['English'],
    this.latitude,
    this.longitude,
    Map<String, String>? procedureFees,
  }) : procedureFees = procedureFees ?? const {};

  bool get hasCoordinates =>
      ClinicDirectionsHelper.hasValidCoordinates(latitude, longitude);
  bool get hasPhysicalClinicLocation =>
      hasCoordinates ||
      ClinicDirectionsHelper.composeAddressQuery(
        clinicName: clinicName,
        clinicAddress: clinicAddress,
        city: city,
        state: state,
        pincode: pincode,
      ).isNotEmpty;
  String get formattedFullAddress => ClinicDirectionsHelper.composeAddressQuery(
        clinicAddress: clinicAddress,
        city: city,
        state: state,
        pincode: pincode,
      );

  DoctorModel copyWith({
    String? status,
    String? onlineStatus,
    String? verificationStatus,
    List<String>? nextAvailableSlots,
    String? consultationFee,
    String? clinicName,
    String? clinicAddress,
    String? city,
    String? state,
    String? pincode,
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
  }) {
    return DoctorModel(
      id: id,
      userId: userId,
      clinicId: clinicId,
      name: name,
      specialty: specialty,
      qualification: qualification,
      experienceYears: experienceYears,
      rating: rating,
      reviewCount: reviewCount,
      clinicName: clinicName ?? this.clinicName,
      phone: phone,
      email: email,
      status: status ?? this.status,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      nextAvailableSlots: nextAvailableSlots ?? this.nextAvailableSlots,
      consultationFee: consultationFee ?? this.consultationFee,
      licenseNumber: licenseNumber,
      photoBytes: photoBytes,
      profileImageUrl: profileImageUrl,
      clinicAddress: clinicAddress ?? this.clinicAddress,
      pincode: pincode ?? this.pincode,
      city: city ?? this.city,
      state: state ?? this.state,
      bio: bio,
      languages: languages,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      procedureFees: procedureFees,
    );
  }

  bool get verified => verificationStatus.trim().toUpperCase() == 'VERIFIED';

  /// Returns true when the doctor's schedule availability is ON and the account is not suspended.
  /// Distinguishes online presence ('Offline' presence while schedule is 'Available') from schedule OFF ('Unavailable').
  bool get isAvailable {
    if (verificationStatus.trim().toUpperCase() == 'SUSPENDED') return false;
    final s = status.trim().toLowerCase();
    return s != 'offline' &&
        s != 'unavailable' &&
        s != 'inactive' &&
        s != 'on leave' &&
        s != 'on_leave' &&
        s != 'off' &&
        s != 'false' &&
        s != 'disabled' &&
        s != 'suspended';
  }

  /// Returns true when the doctor is currently online for live/online consultations.
  bool get isOnline {
    if (!isAvailable) return false;
    final presence = onlineStatus.trim().toLowerCase();
    if (presence.isNotEmpty) {
      return presence == 'online';
    }
    final s = status.trim().toLowerCase();
    return s == 'online' || s == 'available';
  }

  /// Returns true when the doctor is currently marked Busy / In Consultation.
  bool get isBusy {
    final presence = onlineStatus.trim().toLowerCase();
    final s = status.trim().toLowerCase();
    return presence == 'busy' ||
        s == 'busy' ||
        s == 'in consultation' ||
        s == 'in_consultation';
  }

  /// Canonical 5-state display badge ('Online', 'Offline', 'Available', 'Busy', 'Unavailable').
  String get displayStatusBadge {
    if (!isAvailable) return 'Unavailable';
    if (isBusy) return 'Busy';
    final presence = onlineStatus.trim().toLowerCase();
    final s = status.trim().toLowerCase();
    if (presence == 'online' || s == 'online') return 'Online';
    if (presence == 'offline') return 'Available';
    return 'Available';
  }

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
        'clinicId': clinicId,
        'name': name,
        'specialty': specialty,
        'department': department,
        'qualification': qualification,
        'experienceYears': experienceYears,
        'rating': rating,
        'reviewCount': reviewCount,
        'clinicName': clinicName,
        'phone': phone,
        'email': email,
        'status': status,
        'onlineStatus': onlineStatus,
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
        'profileImageUrl': profileImageUrl,
      };

  static ({Uint8List? bytes, String? url}) parseProfilePhoto(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') {
      return (bytes: null, url: null);
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return (bytes: null, url: value);
    }
    if (value.length > 20) {
      try {
        final clean = value.contains(',') ? value.split(',').last : value;
        final decoded = base64Decode(clean);
        if (decoded.isNotEmpty) {
          return (bytes: decoded, url: null);
        }
      } catch (_) {}
    }
    return (bytes: null, url: null);
  }

  bool get hasProfileImage =>
      (photoBytes != null && photoBytes!.isNotEmpty) ||
      (profileImageUrl != null && profileImageUrl!.trim().isNotEmpty);

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    final parsedPhoto = parseProfilePhoto(
      json['photoBase64'] ??
          json['profileImageUrl'] ??
          json['profilePhoto'] ??
          json['profile_photo'] ??
          (json['users'] is Map ? json['users']['biometric_token'] : null) ??
          '',
    );
    final Uint8List? bytes = parsedPhoto.bytes;
    final String? photoUrl = parsedPhoto.url ??
        ((json['profileImageUrl']?.toString().trim().startsWith('http') ?? false)
            ? json['profileImageUrl'].toString().trim()
            : null);
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
      clinicId: (json['clinicId'] ?? json['clinic_id'] ?? (json['clinics'] != null ? json['clinics']['id'] : '') ?? '').toString(),
      name: json['name'] ?? (json['users'] is Map ? (json['users']['name'] ?? '') : '') ?? '',
      specialty: parsedSpecialty,
      department: (json['department'] ?? '').toString().trim(),
      qualification: parsedQual.isNotEmpty
          ? parsedQual
          : (parsedSpecialty.isNotEmpty ? MedicalSpecialtyModel.getDefaultQualificationForSpecialty(parsedSpecialty) : ''),
      experienceYears: int.tryParse((json['experienceYears'] ?? json['experience_years'] ?? '0').toString()) ?? 0,
      rating: ((json['reviewCount'] ?? json['reviews_count'] ?? 0) as num) > 0
          ? ((json['rating'] ?? 0.0) as num).toDouble()
          : 0.0,
      reviewCount: int.tryParse((json['reviewCount'] ?? json['reviews_count'] ?? '0').toString()) ?? 0,
      clinicName: (json['clinicName'] ?? json['clinic_name'] ?? (json['clinics'] != null ? json['clinics']['clinic_name'] : '') ?? '').toString(),
      phone: json['phone'] ?? (json['users'] != null ? json['users']['phone'] : '') ?? '',
      email: json['email'] ?? (json['users'] != null ? json['users']['email'] : '') ?? '',
      status: json['status'] ?? json['availability_status'] ?? 'Available',
      onlineStatus: (json['onlineStatus'] ?? json['online_status'] ?? '').toString(),
      verificationStatus: json['verification_status'] ?? json['verificationStatus'] ?? 'VERIFIED',
      nextAvailableSlots: List<String>.from(json['nextAvailableSlots'] ?? []),
      consultationFee: (json['consultationFee'] ?? json['consultation_fee'] ?? '').toString(),
      licenseNumber: (json['licenseNumber'] ?? json['license_number'] ?? '').toString(),
      photoBytes: bytes,
      profileImageUrl: photoUrl,
      clinicAddress: (json['clinicAddress'] ?? json['clinic_address'] ?? json['location'] ?? (json['clinics'] != null ? json['clinics']['location'] : '') ?? '').toString(),
      pincode: json['pincode'] ?? json['postal_code'] ?? (json['users'] != null ? (json['users']['pincode'] ?? '') : '') ?? '',
      city: json['city'] ?? (json['users'] != null ? (json['users']['city'] ?? '') : '') ?? '',
      state: json['state'] ?? (json['users'] != null ? (json['users']['state'] ?? '') : '') ?? '',
      bio: (json['bio'] ?? json['about'] ?? json['description'] ?? (json['users'] is Map ? (json['users']['bio'] ?? '') : '') ?? '').toString(),
      languages: parsedLanguages,
      latitude: (json['latitude'] ??
                  json['lat'] ??
                  (json['clinics'] is Map ? json['clinics']['latitude'] : null) ??
                  (json['users'] is Map ? json['users']['latitude'] : null)) !=
              null
          ? double.tryParse((json['latitude'] ??
                  json['lat'] ??
                  (json['clinics'] is Map ? json['clinics']['latitude'] : null) ??
                  (json['users'] is Map ? json['users']['latitude'] : null))
              .toString())
          : null,
      longitude: (json['longitude'] ??
                  json['lng'] ??
                  (json['clinics'] is Map ? json['clinics']['longitude'] : null) ??
                  (json['users'] is Map ? json['users']['longitude'] : null)) !=
              null
          ? double.tryParse((json['longitude'] ??
                  json['lng'] ??
                  (json['clinics'] is Map ? json['clinics']['longitude'] : null) ??
                  (json['users'] is Map ? json['users']['longitude'] : null))
              .toString())
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
  String? district;
  String? districtIdentificationStatus;
  List<String> languages;
  Uint8List? photoBytes;
  String? profileImageUrl;

  PatientProfile({
    this.id = '',
    this.name = '',
    this.email = '',
    this.phone = '',
    this.age = '',
    this.gender = '',
    this.bloodGroup = '',
    this.emergencyContact = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.district,
    this.districtIdentificationStatus,
    this.languages = const ['English'],
    this.photoBytes,
    this.profileImageUrl,
  });

  static String cleanString(dynamic value) {
    final s = (value ?? '').toString().trim();
    return s.toLowerCase() == 'null' ? '' : s;
  }

  static String _cleanString(dynamic value) => cleanString(value);

  static ({Uint8List? bytes, String? url}) parseProfilePhoto(dynamic raw) {
    final str = _cleanString(raw);
    if (str.isEmpty) return (bytes: null, url: null);
    if (str.startsWith('http://') || str.startsWith('https://')) {
      return (bytes: null, url: str);
    }
    try {
      final cleanBase64 = str.contains(',') ? str.split(',').last.trim() : str;
      final decoded = base64Decode(cleanBase64);
      if (decoded.isNotEmpty) {
        return (bytes: decoded, url: null);
      }
    } catch (_) {}
    return (bytes: null, url: null);
  }

  bool get hasProfileImage =>
      (photoBytes != null && photoBytes!.isNotEmpty) ||
      (profileImageUrl != null &&
          profileImageUrl!.trim().isNotEmpty &&
          profileImageUrl!.trim().toLowerCase() != 'null');

  bool get hasValidPincode => RegExp(r'^\d{6}$').hasMatch(pincode.trim());

  bool get hasValidAge {
    final trimmed = age.trim();
    if (trimmed.isEmpty || !RegExp(r'^\d+$').hasMatch(trimmed)) return false;
    final parsed = int.tryParse(trimmed);
    return parsed != null && parsed >= 1 && parsed <= 120;
  }

  bool get hasValidGender {
    final trimmed = gender.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }

  bool get hasValidFullName {
    final trimmed = name.trim();
    return trimmed.isNotEmpty &&
        trimmed.toLowerCase() != 'patient' &&
        trimmed.toLowerCase() != 'null' &&
        !trimmed.toLowerCase().startsWith('user_');
  }

  bool get hasValidAddress {
    final trimmed = address.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }

  bool get hasValidLanguages =>
      languages.any((l) => l.trim().isNotEmpty && l.trim().toLowerCase() != 'null');

  bool get hasValidBloodGroup {
    final trimmed = bloodGroup.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }

  bool get isProfileComplete {
    if (PatientProfileRequirementsConfig.requireProfileImage && !hasProfileImage) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requirePincode && !hasValidPincode) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requireAge && !hasValidAge) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requireGender && !hasValidGender) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requireFullName && !hasValidFullName) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requireAddress && !hasValidAddress) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requirePreferredLanguage && !hasValidLanguages) {
      return false;
    }
    if (PatientProfileRequirementsConfig.requireBloodGroup && !hasValidBloodGroup) {
      return false;
    }
    return true;
  }

  List<String> get missingRequiredProfileFields => <String>[
        if (PatientProfileRequirementsConfig.requireProfileImage && !hasProfileImage)
          'Profile image',
        if (PatientProfileRequirementsConfig.requireFullName && !hasValidFullName)
          'Full name',
        if (PatientProfileRequirementsConfig.requireAddress && !hasValidAddress)
          'Address',
        if (PatientProfileRequirementsConfig.requirePincode && !hasValidPincode)
          'Pincode',
        if (PatientProfileRequirementsConfig.requirePreferredLanguage && !hasValidLanguages)
          'Preferred language',
        if (PatientProfileRequirementsConfig.requireAge && !hasValidAge) 'Age',
        if (PatientProfileRequirementsConfig.requireGender && !hasValidGender)
          'Gender',
        if (PatientProfileRequirementsConfig.requireBloodGroup && !hasValidBloodGroup)
          'Blood group',
      ];

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
        'district': district,
        'district_identification_status': districtIdentificationStatus,
        'languages': languages,
        'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
        'profileImageUrl': profileImageUrl,
      };

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    final parsedPhoto = parseProfilePhoto(
      json['photoBase64'] ?? json['profilePhoto'] ?? json['biometric_token'] ?? json['profileImageUrl'],
    );
    final explicitUrl = _cleanString(json['profileImageUrl']);

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
      id: _cleanString(json['id']),
      name: _cleanString(json['name']),
      email: _cleanString(json['email']),
      phone: _cleanString(json['phone']),
      age: _cleanString(json['age'] ?? json['patient_age']),
      gender: _cleanString(json['gender']),
      bloodGroup: _cleanString(json['bloodGroup'] ?? json['blood_group']),
      emergencyContact: _cleanString(json['emergencyContact'] ?? json['emergency_contact']),
      address: _cleanString(json['address'] ?? json['location']),
      city: _cleanString(json['city']),
      state: _cleanString(json['state']),
      pincode: _cleanString(json['pincode'] ?? json['postal_code']),
      district: json['district'] ?? json['district_name'] ?? json['city'],
      districtIdentificationStatus: json['district_identification_status'] ?? 'VERIFIED',
      languages: parsedLangs,
      photoBytes: parsedPhoto.bytes,
      profileImageUrl: explicitUrl.isNotEmpty ? explicitUrl : parsedPhoto.url,
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
  // Smart Hybrid Scheduling Metadata
  String? consultationMode;
  String? scheduledEndTime;
  String? bufferEndTime;
  int? durationMinutes;
  int? bufferMinutes;
  String? actualStartAt;
  String? actualEndAt;
  int delayMinutes;
  String? estimatedStartTime;
  String? rescheduleRequestStatus;
  String? rescheduleRequestedDate;
  String? rescheduleRequestedSlot;
  String? rescheduleRequestReason;
  String? patientDelayChoice;

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
    this.consultationMode,
    this.scheduledEndTime,
    this.bufferEndTime,
    this.durationMinutes,
    this.bufferMinutes,
    this.actualStartAt,
    this.actualEndAt,
    this.delayMinutes = 0,
    this.estimatedStartTime,
    this.rescheduleRequestStatus,
    this.rescheduleRequestedDate,
    this.rescheduleRequestedSlot,
    this.rescheduleRequestReason,
    this.patientDelayChoice,
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
    String? sanitize(String? value) {
      final cleaned = (value ?? '').trim();
      final lower = cleaned.toLowerCase();
      if (cleaned.isEmpty ||
          lower == 'null' ||
          lower == 'dr. specialist' ||
          lower == 'selected doctor') {
        return null;
      }
      return cleaned;
    }

    final assigned = sanitize(assignedDoctorName);
    if (assigned != null) return assigned;

    final lookupIds = <String>[
      if (assignedDoctorId != null && assignedDoctorId!.trim().isNotEmpty)
        assignedDoctorId!.trim(),
      if (preferredDoctorId != null && preferredDoctorId!.trim().isNotEmpty)
        preferredDoctorId!.trim(),
    ];

    for (final targetId in lookupIds) {
      final doc = PatientProblemService().allDoctors.where(
        (d) =>
            d.id == targetId ||
            (d.userId.isNotEmpty && d.userId == targetId) ||
            (d.email.isNotEmpty && d.email.toLowerCase() == targetId.toLowerCase()) ||
            (d.name.isNotEmpty &&
                targetId.toLowerCase().contains(
                      d.name.replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '').trim().toLowerCase(),
                    )),
      ).firstOrNull;
      final resolved = sanitize(doc?.name);
      if (resolved != null) return resolved;
    }

    final preferred = sanitize(preferredDoctorName);
    if (preferred != null) return preferred;

    return '';
  }

  String get displayDoctorSpecialty {
    if (assignedDoctorSpecialty != null &&
        assignedDoctorSpecialty!.trim().isNotEmpty &&
        assignedDoctorSpecialty != 'null' &&
        assignedDoctorSpecialty != 'Dental Specialist' &&
        assignedDoctorSpecialty != 'Medical Specialist') {
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

  /// Resolves the matching registered [DoctorModel] from directory if available.
  DoctorModel? get resolvedDoctor {
    final docs = PatientProblemService().allDoctors;
    if (docs.isEmpty) return null;
    final candidateIds = <String>[
      if (assignedDoctorId != null && assignedDoctorId!.trim().isNotEmpty)
        assignedDoctorId!.trim(),
      if (preferredDoctorId != null && preferredDoctorId!.trim().isNotEmpty)
        preferredDoctorId!.trim(),
    ];
    for (final cid in candidateIds) {
      for (final d in docs) {
        if (d.id == cid || (d.userId.isNotEmpty && d.userId == cid)) {
          return d;
        }
      }
    }
    final targetName = (assignedDoctorName ?? preferredDoctorName ?? '')
        .replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    if (targetName.isNotEmpty && targetName != 'specialist' && targetName != 'null') {
      for (final d in docs) {
        final cleanDoc = d.name
            .replaceAll(RegExp(r'^Dr\.?\s*', caseSensitive: false), '')
            .trim()
            .toLowerCase();
        if (cleanDoc.isNotEmpty && cleanDoc == targetName) {
          return d;
        }
      }
    }
    return null;
  }

  /// Returns real doctor consultation fee (empty string when unset; never invents dummy fees).
  String get displayConsultationFee {
    final direct = (assignedDoctorFee ?? '').trim();
    if (direct.isNotEmpty &&
        direct.toLowerCase() != 'null' &&
        direct != r'$75' &&
        direct != '75') {
      return direct;
    }
    final docFee = (resolvedDoctor?.consultationFee ?? '').trim();
    if (docFee.isNotEmpty &&
        docFee.toLowerCase() != 'null' &&
        docFee != r'$75' &&
        docFee != '75') {
      return docFee;
    }
    return '';
  }

  /// Determines consultation mode ('Online' vs 'In-Person') from real appointment/request attributes.
  String get displayConsultationMode {
    final explicit = (consultationMode ?? '').trim();
    if (explicit.isNotEmpty) {
      return BookingRulesConfig.normalizeConsultationMode(explicit);
    }
    final combined = [
      problemCategory,
      problemDescription,
      symptoms,
      preferredLocation,
      adminNotes ?? '',
    ].join(' ').toLowerCase();
    if (combined.contains('online') ||
        combined.contains('video') ||
        combined.contains('teleconsult') ||
        combined.contains('tele-consult') ||
        combined.contains('immediate consultation')) {
      return 'Online';
    }
    return 'In-Person';
  }

  /// Whether this request represents a patient referral
  bool get isReferral {
    final descLower = problemDescription.toLowerCase();
    if (descLower.startsWith('referral for ') ||
        descLower.contains('referral for ') ||
        descLower.startsWith('referral:')) {
      return true;
    }
    if (adminNotes != null && adminNotes!.contains('REFERRAL_PAYLOAD:')) {
      return true;
    }
    return false;
  }

  /// Extracts the clean clinical referral reason without raw JSON or wrapper text
  String get cleanReferralReason {
    // If adminNotes contains REFERRAL_PAYLOAD, check for clinical_complaint
    if (adminNotes != null && adminNotes!.contains('REFERRAL_PAYLOAD:')) {
      try {
        final jsonStr = adminNotes!.split('REFERRAL_PAYLOAD:').last.trim();
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map && decoded['clinical_complaint'] != null) {
          final complaint = decoded['clinical_complaint'].toString().trim();
          if (complaint.isNotEmpty) return complaint;
        }
      } catch (_) {}
    }
    // If problemDescription is formatted e.g. "Referral for suchi (9087654387): pain"
    if (problemDescription.contains(':')) {
      final afterColon = problemDescription.split(':').sublist(1).join(':').trim();
      if (afterColon.isNotEmpty) {
        return afterColon;
      }
    }
    if (problemDescription.toLowerCase().startsWith('referral for ')) {
      return problemDescription;
    }
    return problemDescription.isNotEmpty ? problemDescription : 'General consultation';
  }

  /// Sanitizes admin guidance or referral notes.
  /// Strictly removes raw JSON, internal payloads (REFERRAL_PAYLOAD:), and database IDs.
  /// Returns meaningful human instructions if present, or null.
  static String? sanitizeAdminGuidance(String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;
    final text = notes.trim();

    // 1. If text contains REFERRAL_PAYLOAD:
    if (text.contains('REFERRAL_PAYLOAD:')) {
      final parts = text.split('REFERRAL_PAYLOAD:');
      final beforeText = parts.first.trim();
      final jsonStr = parts.last.trim();

      String? extractedInstruction;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          final possibleKeys = [
            'instructions',
            'instruction',
            'referral_instructions',
            'admin_notes',
            'adminNotes',
            'admin_guidance',
            'adminGuidance',
            'notes',
            'clinical_notes',
            'guidance',
            'special_instructions',
          ];
          for (final k in possibleKeys) {
            final val = decoded[k]?.toString().trim();
            if (val != null &&
                val.isNotEmpty &&
                !val.startsWith('{') &&
                !val.startsWith('[') &&
                !val.contains('REFERRAL_PAYLOAD:') &&
                !val.contains('referrer_id') &&
                !val.contains('referred_patient_id') &&
                !val.contains('referred_user_id')) {
              extractedInstruction = val;
              break;
            }
          }
        }
      } catch (_) {}

      if (beforeText.isNotEmpty &&
          !beforeText.startsWith('{') &&
          !beforeText.contains('REFERRAL_PAYLOAD:') &&
          !beforeText.contains('referrer_id')) {
        return extractedInstruction != null ? '$beforeText • $extractedInstruction' : beforeText;
      }
      return extractedInstruction;
    }

    // 2. If text is a raw serialized JSON object
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final possibleKeys = [
            'instructions',
            'instruction',
            'referral_instructions',
            'admin_notes',
            'adminNotes',
            'admin_guidance',
            'adminGuidance',
            'notes',
            'clinical_notes',
            'guidance',
            'special_instructions',
          ];
          for (final k in possibleKeys) {
            final val = decoded[k]?.toString().trim();
            if (val != null &&
                val.isNotEmpty &&
                !val.startsWith('{') &&
                !val.startsWith('[') &&
                !val.contains('referrer_id') &&
                !val.contains('referred_patient_id') &&
                !val.contains('referred_user_id')) {
              return val;
            }
          }
          return null; // Suppress pure JSON without human instructions
        }
      } catch (_) {
        return null;
      }
    }

    // 3. If text contains technical database IDs or serialization markers, suppress it
    if (text.contains('referrer_id') ||
        text.contains('referred_user_id') ||
        text.contains('referred_patient_id') ||
        text.contains('"id":') ||
        text.startsWith('{"')) {
      return null;
    }

    // 4. Return clean human-readable text
    return text;
  }

  /// Clean admin guidance getter
  String? get cleanAdminGuidance => sanitizeAdminGuidance(adminNotes);

  /// Returns patient phone with strict authorization check and zero dummy fallback
  String getFormattedPatientPhone({required bool isAuthorized}) {
    final raw = patientPhone.trim();
    if (raw.isEmpty || raw == 'Not Provided' || raw == 'null') {
      return 'Phone not provided';
    }

    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final cleanPhone = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;

    if (!isAuthorized) {
      if (cleanPhone.length >= 4) {
        return '+91 ••••• ••${cleanPhone.substring(cleanPhone.length - 3)}';
      }
      return 'Authorized Doctors Only';
    }

    return cleanPhone.length == 10 ? '+91 $cleanPhone' : (raw.startsWith('+') ? raw : '+91 $raw');
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
        'consultationMode': consultationMode,
        'scheduledEndTime': scheduledEndTime,
        'bufferEndTime': bufferEndTime,
        'durationMinutes': durationMinutes,
        'bufferMinutes': bufferMinutes,
        'actualStartAt': actualStartAt,
        'actualEndAt': actualEndAt,
        'delayMinutes': delayMinutes,
        'estimatedStartTime': estimatedStartTime,
        'rescheduleRequestStatus': rescheduleRequestStatus,
        'rescheduleRequestedDate': rescheduleRequestedDate,
        'rescheduleRequestedSlot': rescheduleRequestedSlot,
        'rescheduleRequestReason': rescheduleRequestReason,
        'patientDelayChoice': patientDelayChoice,
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
      consultationMode: (json['consultationMode'] ?? json['consultation_type'])?.toString(),
      scheduledEndTime: (json['scheduledEndTime'] ?? json['scheduled_end_time'])?.toString(),
      bufferEndTime: (json['bufferEndTime'] ?? json['buffer_end_time'])?.toString(),
      durationMinutes: int.tryParse((json['durationMinutes'] ?? json['duration_minutes'] ?? '').toString()),
      bufferMinutes: int.tryParse((json['bufferMinutes'] ?? json['buffer_minutes'] ?? '').toString()),
      actualStartAt: (json['actualStartAt'] ?? json['actual_start_at'])?.toString(),
      actualEndAt: (json['actualEndAt'] ?? json['actual_end_at'])?.toString(),
      delayMinutes: int.tryParse((json['delayMinutes'] ?? json['delay_minutes'] ?? '0').toString()) ?? 0,
      estimatedStartTime: (json['estimatedStartTime'] ?? json['estimated_start_time'])?.toString(),
      rescheduleRequestStatus: (json['rescheduleRequestStatus'] ??
              (json['reschedule_request'] is Map ? json['reschedule_request']['status'] : null))
          ?.toString(),
      rescheduleRequestedDate: (json['rescheduleRequestedDate'] ??
              (json['reschedule_request'] is Map ? json['reschedule_request']['requestedDate'] : null))
          ?.toString(),
      rescheduleRequestedSlot: (json['rescheduleRequestedSlot'] ??
              (json['reschedule_request'] is Map ? json['reschedule_request']['requestedTimeSlot'] : null))
          ?.toString(),
      rescheduleRequestReason: (json['rescheduleRequestReason'] ??
              (json['reschedule_request'] is Map ? json['reschedule_request']['reason'] : null))
          ?.toString(),
      patientDelayChoice: (json['patientDelayChoice'] ?? json['patient_delay_choice'])?.toString(),
    );
  }
}

/// Central state service for logged in patient, consultation requests, and doctor directory
/// Model representing a Clinic registered in GS HEALTH platform
class ClinicModel {
  final String id;
  final String userId;
  final String clinicName;
  final String location;
  final String clinicAddress;
  final String city;
  final String state;
  final String pincode;
  final double? latitude;
  final double? longitude;
  final int associatedDoctorsCount;
  final String phone;
  final String email;
  final String coverImageUrl;
  final bool isFeatured;
  final String featuredPlan;
  final double rating;
  final int reviewsCount;
  final bool verified;
  final String verificationStatus; // 'VERIFIED', 'PENDING_VERIFICATION', 'REJECTED', 'SUSPENDED'
  final List<String> services;
  final List<Map<String, dynamic>> pricing;

  ClinicModel({
    required this.id,
    this.userId = '',
    required this.clinicName,
    required this.location,
    this.clinicAddress = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.latitude,
    this.longitude,
    this.associatedDoctorsCount = 0,
    this.phone = '',
    this.email = '',
    this.coverImageUrl = '',
    this.isFeatured = false,
    this.featuredPlan = '',
    this.rating = 5.0,
    this.reviewsCount = 0,
    this.verified = true,
    this.verificationStatus = 'VERIFIED',
    List<String>? services,
    List<Map<String, dynamic>>? pricing,
  })  : services = services ?? const [],
        pricing = pricing ?? const [];

  String get displayAddress =>
      clinicAddress.trim().isNotEmpty ? clinicAddress.trim() : location.trim();

  String get cityStatePincode {
    final parts = <String>[
      if (city.trim().isNotEmpty) city.trim(),
      if (state.trim().isNotEmpty) state.trim(),
      if (pincode.trim().isNotEmpty) pincode.trim(),
    ];
    return parts.join(', ');
  }

  factory ClinicModel.fromJson(Map<String, dynamic> json) {
    List<String> servList = [];
    if (json['services'] is List) {
      servList = (json['services'] as List).map((s) => s.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    List<Map<String, dynamic>> priceList = [];
    if (json['pricing'] is List) {
      priceList = (json['pricing'] as List).map((p) => p is Map<String, dynamic> ? p : <String, dynamic>{}).toList();
    }
    final userObj = json['users'] is Map ? json['users'] as Map : (json['user'] is Map ? json['user'] as Map : const {});
    final addr = (json['clinicAddress'] ?? json['clinic_address'] ?? json['location'] ?? json['address'] ?? '').toString().trim();
    final rawLat = json['latitude'] ?? userObj['latitude'];
    final rawLng = json['longitude'] ?? userObj['longitude'];
    final double? parsedLat = rawLat != null ? double.tryParse(rawLat.toString()) : null;
    final double? parsedLng = rawLng != null ? double.tryParse(rawLng.toString()) : null;
    final rawDocCount = json['associatedDoctorsCount'] ?? json['totalDoctors'] ?? 0;
    final int docCount = rawDocCount is int ? rawDocCount : (int.tryParse(rawDocCount.toString()) ?? 0);

    return ClinicModel(
      id: (json['id'] ?? json['clinicId'] ?? json['_id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? userObj['id'] ?? '').toString(),
      clinicName: (json['clinic_name'] ?? json['clinicName'] ?? userObj['name'] ?? '').toString(),
      location: (json['location'] ?? addr).toString(),
      clinicAddress: addr,
      city: (json['city'] ?? userObj['city'] ?? '').toString().trim(),
      state: (json['state'] ?? userObj['state'] ?? '').toString().trim(),
      pincode: (json['pincode'] ?? userObj['pincode'] ?? '').toString().trim(),
      latitude: parsedLat,
      longitude: parsedLng,
      associatedDoctorsCount: docCount,
      phone: (json['phone'] ?? json['contact'] ?? userObj['phone'] ?? '').toString(),
      email: (json['email'] ?? userObj['email'] ?? '').toString(),
      coverImageUrl: (json['cover_image_url'] ?? json['coverImageUrl'] ?? '').toString(),
      isFeatured: json['is_featured'] == true || json['isFeatured'] == true,
      featuredPlan: (json['featured_plan'] ?? json['featuredPlan'] ?? '').toString(),
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
        'userId': userId,
        'clinicName': clinicName,
        'location': location,
        'clinicAddress': clinicAddress,
        'city': city,
        'state': state,
        'pincode': pincode,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'associatedDoctorsCount': associatedDoctorsCount,
        'phone': phone,
        'email': email,
        'coverImageUrl': coverImageUrl,
        'isFeatured': isFeatured,
        'featuredPlan': featuredPlan,
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

  /// Patient-facing available doctors only (excludes doctors whose availability is OFF or suspended).
  List<DoctorModel> get availableDoctors =>
      List.unmodifiable(_allDoctors.where((d) => d.isAvailable));

  /// Returns true when [doc] has availability enabled and is not completely blocked/zero-slot
  /// across the upcoming 7-day booking window in cache.
  bool isDoctorCurrentlyBookable(DoctorModel doc) {
    if (!doc.isAvailable) return false;
    final now = DateTime.now();
    int cachedDays = 0;
    int openDays = 0;
    for (int offset = 1; offset <= 7; offset++) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      final dStr =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      DoctorAvailabilityModel? avail = _availabilityCache['${doc.id}_$dStr'];
      if (avail == null) {
        final prefix = '${doc.id}_${dStr}_';
        for (final entry in _availabilityCache.entries) {
          if (entry.key.startsWith(prefix)) {
            avail = entry.value;
            break;
          }
        }
      }
      if (avail == null && doc.userId.isNotEmpty) {
        avail = _availabilityCache['${doc.userId}_$dStr'];
      }
      if (avail != null) {
        cachedDays++;
        if (!avail.isBlocked && avail.isWorkingDay && avail.availableSlots.isNotEmpty) {
          openDays++;
        }
      }
    }
    if (cachedDays >= 7 && openDays == 0) {
      return false;
    }
    return true;
  }

  /// Resolves deduplicated, bookable doctors matching [specialtyName], falling back to
  /// available General Medicine doctors when the selected specialty has zero bookable doctors.
  ({
    List<DoctorModel> doctors,
    bool usedGeneralMedicineFallback,
    String resolvedSpecialty,
  }) getAvailableDoctorsForSpecialtyWithFallback(
    String specialtyName, {
    String searchQuery = '',
  }) {
    final resolvedSpecialty = SpecialtyClinicalConfig.forSpecialty(specialtyName).name;

    // 1. Deduplicate bookable doctors by canonical identity (userId > email > phone > name|specialty)
    final seenKeys = <String>{};
    final uniqueBookable = <DoctorModel>[];
    for (final d in _allDoctors) {
      if (!isDoctorCurrentlyBookable(d)) continue;
      final canonicalKey = d.userId.trim().isNotEmpty
          ? 'uid:${d.userId.trim().toLowerCase()}'
          : (d.email.trim().isNotEmpty
              ? 'email:${d.email.trim().toLowerCase()}'
              : (d.phone.trim().isNotEmpty
                  ? 'phone:${d.phone.trim()}'
                  : 'ns:${d.name.trim().toLowerCase()}|${d.specialty.trim().toLowerCase()}'));
      if (seenKeys.add(canonicalKey)) {
        uniqueBookable.add(d);
      }
    }

    bool matchesSpec(DoctorModel d, String targetSpec) {
      final targetNorm = SpecialtyClinicalConfig.forSpecialty(targetSpec).name.toLowerCase();
      final docNorm = SpecialtyClinicalConfig.forSpecialty(d.specialty).name.toLowerCase();
      if (docNorm == targetNorm) return true;
      return MedicalSpecialtyModel.matchesSpecialtyFilter(
        d.specialty,
        targetSpec,
        specialties: _specialties,
      );
    }

    final q = searchQuery.trim().toLowerCase();
    final qMatchesSelectedSpec = q.isEmpty ||
        resolvedSpecialty.toLowerCase().contains(q) ||
        SpecialtyClinicalConfig.forSpecialty(resolvedSpecialty).aliases.any((a) => a.contains(q));

    final primaryMatches = uniqueBookable.where((d) {
      if (!matchesSpec(d, resolvedSpecialty)) return false;
      if (q.isEmpty || qMatchesSelectedSpec) return true;
      return d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q) ||
          d.clinicName.toLowerCase().contains(q);
    }).toList();

    if (primaryMatches.isNotEmpty) {
      return (
        doctors: primaryMatches,
        usedGeneralMedicineFallback: false,
        resolvedSpecialty: resolvedSpecialty,
      );
    }

    if (resolvedSpecialty.toLowerCase() != 'general medicine') {
      final gmFallback = uniqueBookable.where((d) => matchesSpec(d, 'General Medicine')).toList();
      if (gmFallback.isNotEmpty) {
        return (
          doctors: gmFallback,
          usedGeneralMedicineFallback: true,
          resolvedSpecialty: resolvedSpecialty,
        );
      }
    }

    return (
      doctors: const <DoctorModel>[],
      usedGeneralMedicineFallback: false,
      resolvedSpecialty: resolvedSpecialty,
    );
  }

  void addTestDoctor(DoctorModel doc) {
    _allDoctors.add(doc);
    notifyListeners();
  }

  void addTestClinic(ClinicModel clinic) {
    _allClinics.add(clinic);
    notifyListeners();
  }

  void addTestRequest(PatientConsultationRequest req) {
    _requests.add(req);
    notifyListeners();
  }

  void addTestAssignedRequest(PatientConsultationRequest req) {
    _dentistAssignedRequests.add(req);
    if (!_requests.any((r) => r.id == req.id)) {
      _requests.add(req);
    }
    notifyListeners();
  }

  void addTestPatient(PatientProfile patient) {
    _allPatients.add(patient);
    notifyListeners();
  }

  @visibleForTesting
  void addTestSubAdminForTesting(Map<String, dynamic> subAdmin) {
    _subAdmins.add(Map<String, dynamic>.from(subAdmin));
    notifyListeners();
  }

  void setTestDistricts(List<Map<String, dynamic>> list) {
    _districts.clear();
    _districts.addAll(list);
    notifyListeners();
  }

  void setTestAssignmentHistory(List<Map<String, dynamic>> list) {
    _assignmentHistory.clear();
    _assignmentHistory.addAll(list);
    notifyListeners();
  }

  PatientProfile? _pendingReferralPatient;
  PatientProfile? get pendingReferralPatient => _pendingReferralPatient;

  void setPendingReferralPatient(PatientProfile? p) {
    _pendingReferralPatient = p;
    notifyListeners();
  }

  void clearPendingReferralPatient() {
    _pendingReferralPatient = null;
    notifyListeners();
  }

  // Helper to safely access auth user ID without throwing when uninitialized
  String? get _safeAuthUserId {
    return SupabaseService.safeCurrentUser?.id;
  }

  // Helper to safely access auth user email without throwing when uninitialized
  String? get _safeAuthUserEmail {
    return SupabaseService.safeCurrentUser?.email?.trim().toLowerCase();
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

  static int _notificationSeq = 0;

  void addNotification({
    required String recipientRole,
    required String recipientId,
    required String title,
    required String message,
  }) {
    final notif = AppNotificationModel(
      id: 'NOTIF-${DateTime.now().millisecondsSinceEpoch}-${++_notificationSeq}',
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

      // 4b. Load In-App Notifications
      final notifStr = prefs.getString('dentaguru_app_notifications');
      if (notifStr != null && notifStr.isNotEmpty) {
        try {
          final List list = jsonDecode(notifStr);
          _appNotifications.clear();
          for (final item in list) {
            if (item is Map) {
              _appNotifications.add(AppNotificationModel.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        } catch (_) {}
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
          _subAdminDistricts.clear();
          if (saMap['assignedDistricts'] is List) {
            for (final d in saMap['assignedDistricts']) {
              if (d is Map) {
                _subAdminDistricts.add(Map<String, dynamic>.from(d));
              } else if (d != null) {
                _subAdminDistricts.add({'id': d.toString(), 'name': d.toString()});
              }
            }
          }
        } catch (_) {}
      }

      final savedDistrictsJson = prefs.getString('dentaguru_districts_cache');
      if (savedDistrictsJson != null && savedDistrictsJson.isNotEmpty) {
        try {
          final List decoded = jsonDecode(savedDistrictsJson);
          _districts.clear();
          _districts.addAll(decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
        } catch (_) {}
      }

      // 5b2. Load Clinic Session
      final clinicSessionStr = prefs.getString('dentaguru_clinic_session');
      if (clinicSessionStr != null && clinicSessionStr.isNotEmpty) {
        try {
          final Map<String, dynamic> cMap = jsonDecode(clinicSessionStr);
          _isClinicMode = cMap['isClinicMode'] == true;
          _authenticatedClinicId = (cMap['id'] ?? '').toString();
          _authenticatedClinicName = (cMap['clinicName'] ?? '').toString();
          _authenticatedClinicLocation = (cMap['location'] ?? '').toString();
          _authenticatedClinicPhone = (cMap['phone'] ?? '').toString();
          _authenticatedClinicEmail = (cMap['email'] ?? '').toString();
          _authenticatedClinicIsFeatured = cMap['isFeatured'] == true;
          _authenticatedClinicFeaturedPlan = (cMap['featuredPlan'] ?? '').toString();
          _authenticatedClinicCoverUrl = (cMap['coverImageUrl'] ?? '').toString();
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

  // District Management & Jurisdiction State
  final List<Map<String, dynamic>> _districts = [];
  List<Map<String, dynamic>> get districts => List.unmodifiable(_districts);

  final List<Map<String, dynamic>> _subAdminDistricts = [];
  List<Map<String, dynamic>> get subAdminDistricts => List.unmodifiable(_subAdminDistricts);

  // Patient Assignment & Immutable Audit Trail State
  final List<Map<String, dynamic>> _assignmentHistory = [];
  List<Map<String, dynamic>> get assignmentHistory => List.unmodifiable(_assignmentHistory);

  Map<String, dynamic> _assignmentStats = {};
  Map<String, dynamic> get assignmentStats => Map.unmodifiable(_assignmentStats);

  final List<Map<String, dynamic>> _districtReports = [];
  List<Map<String, dynamic>> get districtReports => List.unmodifiable(_districtReports);

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

  /// Check whether the current user (Sub-Admin or Main Admin) has jurisdiction over a district
  bool canAccessDistrict(String? districtIdOrName) {
    if (!_isSubAdminMode) return true; // Main Admin has global jurisdiction
    if (_subAdminDistricts.isEmpty) return true; // If no districts assigned, fallback
    if (districtIdOrName == null || districtIdOrName.trim().isEmpty) return true;
    final target = districtIdOrName.trim().toLowerCase();
    for (final d in _subAdminDistricts) {
      final dId = (d['id'] ?? d['district_id'] ?? '').toString().toLowerCase();
      final dName = (d['name'] ?? d['district_name'] ?? '').toString().toLowerCase();
      if (dId == target || dName == target || target.contains(dName) || dName.contains(target)) {
        return true;
      }
    }
    return false;
  }

  /// Get patients filtered strictly by Sub-Admin assigned districts
  List<PatientProfile> getPatientsForCurrentRole() {
    if (!_isSubAdminMode || _subAdminDistricts.isEmpty) {
      return allPatients;
    }
    return allPatients.where((p) {
      final pDistrict = (p.district ?? '').trim().toLowerCase();
      final pCity = p.city.trim().toLowerCase();
      return _subAdminDistricts.any((d) {
        final dId = (d['id'] ?? '').toString().toLowerCase();
        final dName = (d['name'] ?? '').toString().toLowerCase();
        return (pDistrict.isNotEmpty && (pDistrict == dName || pDistrict == dId)) ||
               (pCity.isNotEmpty && (pCity == dName || pCity.contains(dName) || dName.contains(pCity)));
      });
    }).toList();
  }

  /// Get dentists filtered strictly by Sub-Admin assigned districts
  List<DoctorModel> getDentistsForCurrentRole() {
    if (!_isSubAdminMode || _subAdminDistricts.isEmpty) {
      return allDoctors;
    }
    return allDoctors.where((d) {
      final docCity = d.city.trim().toLowerCase();
      return _subAdminDistricts.any((dist) {
        final distName = (dist['name'] ?? '').toString().toLowerCase();
        return docCity.isNotEmpty && (docCity == distName || docCity.contains(distName) || distName.contains(docCity));
      });
    }).toList();
  }

  /// Get patient problem requests filtered strictly by Sub-Admin assigned districts
  List<PatientConsultationRequest> getRequestsForCurrentRole() {
    if (!_isSubAdminMode || _subAdminDistricts.isEmpty) {
      return requests;
    }
    return requests.where((r) {
      final rCity = r.city.trim().toLowerCase();
      return _subAdminDistricts.any((dist) {
        final distName = (dist['name'] ?? '').toString().toLowerCase();
        return rCity.isNotEmpty && (rCity == distName || rCity.contains(distName) || distName.contains(rCity));
      });
    }).toList();
  }

  void setSubAdminSession({
    required String id,
    required String name,
    required String email,
    required String phone,
    required List<String> permissions,
    List<dynamic>? assignedDistricts,
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
    _subAdminDistricts.clear();
    if (assignedDistricts != null) {
      for (final d in assignedDistricts) {
        if (d is Map<String, dynamic>) {
          _subAdminDistricts.add(d);
        } else if (d is Map) {
          _subAdminDistricts.add(Map<String, dynamic>.from(d));
        } else if (d != null) {
          _subAdminDistricts.add({'id': d.toString(), 'name': d.toString()});
        }
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
    _subAdminDistricts.clear();
    _saveToStorage();
    notifyListeners();
  }

  // Clinic Session State & Per-Clinic Visual Cache
  bool _isClinicMode = false;
  String _authenticatedClinicId = '';
  String _authenticatedClinicName = '';
  String _authenticatedClinicLocation = '';
  String _authenticatedClinicPhone = '';
  String _authenticatedClinicEmail = '';
  bool _authenticatedClinicIsFeatured = false;
  String _authenticatedClinicFeaturedPlan = '';
  String _authenticatedClinicCoverUrl = '';
  Uint8List? _authenticatedClinicCoverBytes;
  final Map<String, Uint8List> _clinicCoverBytesByKey = {};
  final Map<String, String> _clinicCoverUrlByKey = {};
  final Map<String, bool> _clinicFeaturedByKey = {};
  final Map<String, String> _clinicFeaturedPlanByKey = {};

  bool get isClinicMode => _isClinicMode;
  String get authenticatedClinicId => _authenticatedClinicId;
  String get authenticatedClinicName => _authenticatedClinicName;
  String get authenticatedClinicLocation => _authenticatedClinicLocation;
  String get authenticatedClinicPhone => _authenticatedClinicPhone;
  String get authenticatedClinicEmail => _authenticatedClinicEmail;
  bool get authenticatedClinicIsFeatured => _authenticatedClinicIsFeatured;
  String get authenticatedClinicFeaturedPlan => _authenticatedClinicFeaturedPlan;
  String get authenticatedClinicCoverUrl => _authenticatedClinicCoverUrl;
  Uint8List? get authenticatedClinicCoverBytes => _authenticatedClinicCoverBytes;

  void setAuthenticatedClinicSession({
    String? id,
    required String clinicName,
    String location = '',
    String? phone,
    String? email,
    bool? isFeatured,
    String? featuredPlan,
    String? coverImageUrl,
    Uint8List? coverImageBytes,
  }) {
    final cleanName = clinicName.trim();
    final cleanId = (id ?? '').trim();
    _isClinicMode = true;
    if (cleanId.isNotEmpty) _authenticatedClinicId = cleanId;
    if (cleanName.isNotEmpty) _authenticatedClinicName = cleanName;
    if (location.trim().isNotEmpty) _authenticatedClinicLocation = location.trim();
    if (phone != null && phone.trim().isNotEmpty) _authenticatedClinicPhone = phone.trim();
    if (email != null && email.trim().isNotEmpty) _authenticatedClinicEmail = email.trim();
    if (isFeatured != null) _authenticatedClinicIsFeatured = isFeatured;
    if (featuredPlan != null && featuredPlan.trim().isNotEmpty) {
      _authenticatedClinicFeaturedPlan = featuredPlan.trim();
    }
    if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty) {
      _authenticatedClinicCoverUrl = coverImageUrl.trim();
    }
    if (coverImageBytes != null) {
      _authenticatedClinicCoverBytes = coverImageBytes;
    }

    final cacheKey = (cleanId.isNotEmpty ? cleanId : cleanName).toLowerCase();
    if (cacheKey.isNotEmpty) {
      if (coverImageBytes != null) _clinicCoverBytesByKey[cacheKey] = coverImageBytes;
      if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty) {
        _clinicCoverUrlByKey[cacheKey] = coverImageUrl.trim();
      }
      if (isFeatured != null) _clinicFeaturedByKey[cacheKey] = isFeatured;
      if (featuredPlan != null && featuredPlan.trim().isNotEmpty) {
        _clinicFeaturedPlanByKey[cacheKey] = featuredPlan.trim();
      }
    }

    if (cleanName.isNotEmpty) {
      final existingIdx = _allClinics.indexWhere((c) =>
          (cleanId.isNotEmpty && c.id == cleanId) ||
          c.clinicName.trim().toLowerCase() == cleanName.toLowerCase());
      if (existingIdx != -1) {
        final existing = _allClinics[existingIdx];
        if (_authenticatedClinicLocation.isEmpty && existing.location.isNotEmpty) {
          _authenticatedClinicLocation = existing.location;
        }
        _allClinics[existingIdx] = ClinicModel(
          id: existing.id,
          userId: existing.userId,
          clinicName: cleanName,
          location: _authenticatedClinicLocation.isNotEmpty ? _authenticatedClinicLocation : existing.location,
          phone: _authenticatedClinicPhone.isNotEmpty ? _authenticatedClinicPhone : existing.phone,
          coverImageUrl: _authenticatedClinicCoverUrl.isNotEmpty ? _authenticatedClinicCoverUrl : existing.coverImageUrl,
          isFeatured: isFeatured ?? existing.isFeatured,
          featuredPlan: _authenticatedClinicFeaturedPlan.isNotEmpty ? _authenticatedClinicFeaturedPlan : existing.featuredPlan,
          rating: existing.rating,
          reviewsCount: existing.reviewsCount,
          verified: existing.verified,
          verificationStatus: existing.verificationStatus,
          services: existing.services,
          pricing: existing.pricing,
        );
      } else {
        _allClinics.insert(
          0,
          ClinicModel(
            id: cleanId.isNotEmpty ? cleanId : 'CLN-${DateTime.now().millisecondsSinceEpoch}',
            clinicName: cleanName,
            location: _authenticatedClinicLocation,
            phone: _authenticatedClinicPhone,
            coverImageUrl: _authenticatedClinicCoverUrl,
            isFeatured: _authenticatedClinicIsFeatured,
            featuredPlan: _authenticatedClinicFeaturedPlan,
            verified: true,
            verificationStatus: 'VERIFIED',
          ),
        );
      }
    }

    _saveToStorage();
    notifyListeners();
  }

  Future<void> clearClinicSession() async {
    _isClinicMode = false;
    _authenticatedClinicId = '';
    _authenticatedClinicName = '';
    _authenticatedClinicLocation = '';
    _authenticatedClinicPhone = '';
    _authenticatedClinicEmail = '';
    _authenticatedClinicIsFeatured = false;
    _authenticatedClinicFeaturedPlan = '';
    _authenticatedClinicCoverUrl = '';
    _authenticatedClinicCoverBytes = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dentaguru_clinic_session');
    } catch (_) {}
    notifyListeners();
  }

  Future<void>? _syncAllInFlight;

  Future<void> syncAllDataFromApi() {
    if (_syncAllInFlight != null) return _syncAllInFlight!;
    final future = _runSyncAllDataFromApi();
    _syncAllInFlight = future;
    future.whenComplete(() {
      if (identical(_syncAllInFlight, future)) {
        _syncAllInFlight = null;
      }
    });
    return future;
  }

  Future<void> _runSyncAllDataFromApi() async {
    try {
      await Future.wait([
        syncSpecialtiesFromApi(),
        syncPatientsFromApi(),
        syncClinicsFromApi(),
        syncDoctorsFromApi(),
        syncMedicalRecordsFromApi(),
        syncSubAdminsFromApi(),
        syncDistrictsFromApi(),
        syncMyDoctorsFromApi(),
      ]);
      final sessRoleLower = (SessionService().currentSession?.role ?? '').toLowerCase();
      final isAdminOrSubAdmin = _isAdminMode || _isSubAdminMode || sessRoleLower.contains('admin');
      await Future.wait([
        syncAppointmentsFromApi(),
        syncProblemRequestsFromApi(),
        syncDentistAssignedRequestsFromApi(),
        syncReferralsFromApi(),
        syncDoctorReferralsFromApi(),
        if (isAdminOrSubAdmin) syncAdminReferralsFromApi(),
        if (_isClinicMode || sessRoleLower.contains('clinic'))
          syncClinicReferralsFromApi(),
        syncNotificationsFromApi(),
        syncAssignmentStatsFromApi(),
        syncAssignmentHistoryFromApi(),
        if (_isSubAdminMode && _subAdminId.isNotEmpty) syncCurrentSubAdminDistrictsFromApi(),
      ]);
    } catch (e) {
      debugPrint('Error in syncAllDataFromApi: $e');
    }
  }

  Future<void> syncSubAdminsFromApi() async {
    try {
      final api = ApiService();
      final list = await api.fetchSubAdmins();
      if (list.isEmpty && !api.lastFetchSubAdminsSucceeded) {
        return;
      }
      final seenIds = <String>{};
      final seenEmails = <String>{};
      final seenPhones = <String>{};
      final fresh = <Map<String, dynamic>>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = (item['id'] ?? '').toString().trim();
        final email = (item['email'] ?? '').toString().trim().toLowerCase();
        final phoneDigits = (item['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        final phone10 = phoneDigits.length >= 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;
        if (id.isNotEmpty && !seenIds.add(id)) continue;
        if (email.isNotEmpty && !seenEmails.add(email)) continue;
        if (phone10.length >= 10 && !seenPhones.add(phone10)) continue;
        final rawStatus = (item['status'] ?? 'ACTIVE').toString().trim().toUpperCase();
        item['status'] = (rawStatus == 'DEACTIVATED' || rawStatus == 'DISABLED') ? 'INACTIVE' : rawStatus;
        fresh.add(item);
      }
      _subAdmins
        ..clear()
        ..addAll(fresh);
      notifyListeners();
    } catch (e) {
      debugPrint('Sync sub-admins error: $e');
    }
  }

  Future<void> syncDistrictsFromApi() async {
    try {
      final list = await ApiService().fetchAdminDistricts();
      if (list.isNotEmpty) {
        final seenIds = <String>{};
        final seenNames = <String>{};
        final fresh = <Map<String, dynamic>>[];
        for (final raw in list) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final id = (item['id'] ?? '').toString().trim();
          final name = (item['name'] ?? item['district_name'] ?? '').toString().trim().toLowerCase();
          if (id.isNotEmpty && !seenIds.add(id)) continue;
          if (name.isNotEmpty && !seenNames.add(name)) continue;
          fresh.add(item);
        }
        _districts
          ..clear()
          ..addAll(fresh);
        _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync districts error: $e');
    }
  }

  Future<void> syncCurrentSubAdminDistrictsFromApi() async {
    if (_subAdminId.isEmpty) return;
    try {
      final list = await ApiService().fetchSubAdminDistricts(_subAdminId);
      if (list.isNotEmpty) {
        _subAdminDistricts.clear();
        for (final item in list) {
          _subAdminDistricts.add(Map<String, dynamic>.from(item));
        }
        _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync current subadmin districts error: $e');
    }
  }

  Future<void> syncAssignmentStatsFromApi() async {
    try {
      final stats = await ApiService().fetchAssignmentStatistics();
      if (stats.isNotEmpty) {
        _assignmentStats = Map<String, dynamic>.from(stats);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync assignment stats error: $e');
    }
  }

  Future<void> syncAssignmentHistoryFromApi({
    String? patientId,
    String? dentistId,
    String? districtId,
    String? assignedBy,
    String? assignmentSource,
    String? status,
  }) async {
    try {
      final res = await ApiService().fetchAssignmentHistory(
        patientId: patientId,
        dentistId: dentistId,
        districtId: districtId,
        assignedBy: assignedBy,
        assignmentSource: assignmentSource,
        status: status,
      );
      if (res['success'] == true && res['history'] is List) {
        final seenIds = <String>{};
        final fresh = <Map<String, dynamic>>[];
        for (final raw in res['history']) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final id = (item['id'] ?? '').toString().trim();
          if (id.isNotEmpty && !seenIds.add(id)) continue;
          fresh.add(item);
        }
        _assignmentHistory
          ..clear()
          ..addAll(fresh);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync assignment history error: $e');
    }
  }

  Future<void> syncDistrictReportsFromApi() async {
    try {
      final list = await ApiService().fetchDistrictReports();
      if (list.isNotEmpty) {
        _districtReports.clear();
        for (final item in list) {
          _districtReports.add(Map<String, dynamic>.from(item));
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync district reports error: $e');
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
    List<String>? districtIds,
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
        districtIds: districtIds,
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

  Future<bool> updateSubAdminDetails({
    required String id,
    String? name,
    String? phone,
    String? password,
    String? status,
    List<String>? permissions,
    List<String>? districtIds,
  }) async {
    try {
      final res = await ApiService().updateSubAdmin(
        id: id,
        name: name,
        phone: phone,
        password: password,
        status: status,
        permissions: permissions,
        districtIds: districtIds,
      );
      if (res['success'] == true) {
        await syncSubAdminsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('updateSubAdminDetails error: $e');
    }
    return false;
  }

  Future<bool> assignSubAdminDistricts(String subAdminId, List<String> districtIds) async {
    try {
      final res = await ApiService().assignSubAdminDistricts(subAdminId, districtIds);
      if (res['success'] == true) {
        await syncSubAdminsFromApi();
        await syncDistrictsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('assignSubAdminDistricts error: $e');
    }
    return false;
  }

  Future<bool> removeSubAdminDistrict(String subAdminId, String districtId) async {
    try {
      final ok = await ApiService().removeSubAdminDistrict(subAdminId, districtId);
      if (ok) {
        await syncSubAdminsFromApi();
        await syncDistrictsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('removeSubAdminDistrict error: $e');
    }
    return false;
  }

  Future<bool> updateSubAdminPermissions(String subAdminId, List<String> permissions) async {
    try {
      final res = await ApiService().updateSubAdminPermissions(subAdminId, permissions);
      if (res['success'] == true) {
        await syncSubAdminsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('updateSubAdminPermissions error: $e');
    }
    return false;
  }

  Future<bool> createDistrict({
    required String name,
    required String state,
    String? code,
    bool isActive = true,
  }) async {
    try {
      final res = await ApiService().createDistrict(
        name: name,
        state: state,
        code: code,
        isActive: isActive,
      );
      if (res['success'] == true) {
        await syncDistrictsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('createDistrict error: $e');
    }
    return false;
  }

  Future<bool> updateDistrict({
    required String id,
    required String name,
    required String state,
    String? code,
    bool? isActive,
  }) async {
    try {
      final res = await ApiService().updateDistrict(
        id: id,
        name: name,
        state: state,
        code: code,
        isActive: isActive,
      );
      if (res['success'] == true) {
        await syncDistrictsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('updateDistrict error: $e');
    }
    return false;
  }

  Future<bool> toggleDistrictStatus(String id, bool isActive) async {
    try {
      final ok = await ApiService().toggleDistrictStatus(id, isActive);
      if (ok) {
        await syncDistrictsFromApi();
        return true;
      }
    } catch (e) {
      debugPrint('toggleDistrictStatus error: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>> assignPatientToDoctor({
    required String patientId,
    required String dentistId,
    String? clinicId,
    String? districtId,
    String? reason,
    String? notes,
    String? scheduledDate,
    String? timeSlot,
  }) async {
    try {
      final res = await ApiService().assignPatientToDoctor(
        patientId: patientId,
        dentistId: dentistId,
        clinicId: clinicId,
        districtId: districtId,
        reason: reason,
        notes: notes,
        scheduledDate: scheduledDate,
        timeSlot: timeSlot,
      );
      if (res['success'] == true) {
        await syncAssignmentHistoryFromApi();
        await syncAssignmentStatsFromApi();
        await syncAllDataFromApi();
      }
      return res;
    } catch (e) {
      debugPrint('assignPatientToDoctor error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> reassignPatient({
    required String patientId,
    required String newDentistId,
    String? previousAssignmentId,
    String? reason,
    String? notes,
  }) async {
    try {
      final res = await ApiService().reassignPatient(
        patientId: patientId,
        newDentistId: newDentistId,
        previousAssignmentId: previousAssignmentId,
        reason: reason,
        notes: notes,
      );
      if (res['success'] == true) {
        await syncAssignmentHistoryFromApi();
        await syncAssignmentStatsFromApi();
        await syncAllDataFromApi();
      }
      return res;
    } catch (e) {
      debugPrint('reassignPatient error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  void updateSubAdminStatusLocally(String id, String status) {
    final idx = _subAdmins.indexWhere((s) => (s['id'] ?? '').toString() == id);
    if (idx != -1) {
      final norm = status.trim().toUpperCase();
      _subAdmins[idx]['status'] = (norm == 'DEACTIVATED' || norm == 'DISABLED') ? 'INACTIVE' : norm;
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
    _myCreatedPatientReferrals.clear();
    _doctorReceivedPatientReferrals.clear();
    _receivedForMePatientReferrals.clear();
    _clinicPatientReferrals.clear();
    _adminPatientReferrals.clear();
    _allDoctors.clear();
    _allClinics.clear();
    _appNotifications.clear();
    _districts.clear();
    _subAdminDistricts.clear();
    _assignmentHistory.clear();
    _districtReports.clear();
    _assignmentStats.clear();
    currentPatient = PatientProfile();
    _userPhotoCache.clear();
    currentDoctor = null;
    _isClinicMode = false;
    _authenticatedClinicId = '';
    _authenticatedClinicName = '';
    _authenticatedClinicLocation = '';
    _authenticatedClinicPhone = '';
    _authenticatedClinicEmail = '';
    _authenticatedClinicIsFeatured = false;
    _authenticatedClinicFeaturedPlan = '';
    _authenticatedClinicCoverUrl = '';
    _authenticatedClinicCoverBytes = null;
    _clinicCoverBytesByKey.clear();
    _clinicCoverUrlByKey.clear();
    _clinicFeaturedByKey.clear();
    _clinicFeaturedPlanByKey.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> syncPatientsFromApi() async {
    try {
      final list = await ApiService().fetchPatients();
      if (list.isNotEmpty) {
        final seenIds = <String>{};
        final seenEmails = <String>{};
        final seenPhones = <String>{};
        final freshPatients = <PatientProfile>[];
        for (final item in list) {
          if (item is! Map) continue;
          final id = (item['id'] ?? '').toString().trim();
          String name = (item['name'] ?? '').toString().trim();
          final email = (item['email'] ?? '').toString().trim();
          final phone = (item['phone'] ?? '').toString().trim();
          final role = (item['role'] ?? '').toString().trim().toLowerCase();

          final isNonPatient = (role.contains('admin') && !email.contains('patient')) ||
              role == 'dentist' ||
              role == 'doctor' ||
              role == 'clinic';
          if (isNonPatient) {
            continue;
          }

          final emailLower = email.toLowerCase();
          final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
          final phone10 = phoneDigits.length >= 10
              ? phoneDigits.substring(phoneDigits.length - 10)
              : phoneDigits;
          if (id.isNotEmpty && !seenIds.add(id)) continue;
          if (emailLower.isNotEmpty && !seenEmails.add(emailLower)) continue;
          if (phone10.length >= 10 && !seenPhones.add(phone10)) continue;

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
          final bloodGroup = (rawBlood.isNotEmpty && rawBlood != 'null') ? rawBlood : '';
          final rawGender = (item['gender'] ?? tokenMeta['gender'] ?? '').toString().trim();
          final gender = (rawGender.isNotEmpty && rawGender != 'null') ? rawGender : '';
          final emergencyContact = (item['emergency_contact'] ?? item['emergencyContact'] ?? tokenMeta['emergencyContact'] ?? '').toString().trim();

          final city = (item['city'] ?? tokenMeta['city'] ?? item['location_city'] ?? '').toString();
          final pincode = (item['pincode'] ?? tokenMeta['pincode'] ?? item['postal_code'] ?? '').toString();
          final state = (item['state'] ?? tokenMeta['state'] ?? '').toString();
          final address = (item['address'] ?? tokenMeta['address'] ?? item['location'] ?? '').toString();

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

          final rawPhotoToken = item['profilePhoto'] ?? item['biometric_token'] ?? tokenMeta['profilePhoto'];
          final parsedPhoto = PatientProfile.parseProfilePhoto(rawPhotoToken);

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
            photoBytes: parsedPhoto.bytes,
            profileImageUrl: parsedPhoto.url,
          );
          freshPatients.add(pProfile);

          final authEmail = _safeAuthUserEmail;
          final sess = SessionService().currentSession;
          final sessPhoneDigits = (sess?.phone ?? '').replaceAll(RegExp(r'\D'), '');
          final itemPhoneDigits = phone.replaceAll(RegExp(r'\D'), '');
          final sessPhone10 = sessPhoneDigits.length >= 10
              ? sessPhoneDigits.substring(sessPhoneDigits.length - 10)
              : sessPhoneDigits;
          final itemPhone10 = itemPhoneDigits.length >= 10
              ? itemPhoneDigits.substring(itemPhoneDigits.length - 10)
              : itemPhoneDigits;
          final isCurrentPatientMatch =
              (authEmail != null && authEmail.isNotEmpty && authEmail.toLowerCase() == email.toLowerCase()) ||
              (sess != null && sess.role.toLowerCase() == 'patient' && sess.userId.isNotEmpty && sess.userId == id) ||
              (sessPhone10.isNotEmpty && itemPhone10.isNotEmpty && sessPhone10 == itemPhone10) ||
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
            if (parsedPhoto.bytes != null) currentPatient.photoBytes = parsedPhoto.bytes;
            if (parsedPhoto.url != null) currentPatient.profileImageUrl = parsedPhoto.url;
          }
        }
        _allPatients
          ..clear()
          ..addAll(freshPatients);
      }
      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync patients error: $e');
    }
  }

  /// Syncs the currently authenticated Patient's own profile from backend/Supabase.
  Future<void> syncCurrentPatientProfileFromApi() async {
    try {
      final sess = SessionService().currentSession;
      if (sess == null || sess.role.trim().toLowerCase() != 'patient') return;
      final remoteUser = await ApiService().fetchCurrentPatientProfile(patientId: sess.userId);
      if (remoteUser == null) return;

      final parsedPhoto = PatientProfile.parseProfilePhoto(remoteUser['profilePhoto']);
      final rAge = PatientProfile._cleanString(remoteUser['age']);
      final rGender = PatientProfile._cleanString(remoteUser['gender']);
      final rPincode = PatientProfile._cleanString(remoteUser['pincode']);
      final rCity = PatientProfile._cleanString(remoteUser['city']);
      final rName = PatientProfile._cleanString(remoteUser['name']);
      final rPhone = PatientProfile._cleanString(remoteUser['phone']);
      final rEmail = PatientProfile._cleanString(remoteUser['email']);

      if (remoteUser['id'] != null) currentPatient.id = remoteUser['id'].toString();
      if (rName.isNotEmpty) currentPatient.name = rName;
      if (rPhone.isNotEmpty) currentPatient.phone = rPhone;
      if (rEmail.isNotEmpty) currentPatient.email = rEmail;
      if (rAge.isNotEmpty) currentPatient.age = rAge;
      if (rGender.isNotEmpty) currentPatient.gender = rGender;
      if (rPincode.isNotEmpty) currentPatient.pincode = rPincode;
      if (rCity.isNotEmpty) currentPatient.city = rCity;
      if (parsedPhoto.bytes != null) currentPatient.photoBytes = parsedPhoto.bytes;
      if (parsedPhoto.url != null) currentPatient.profileImageUrl = parsedPhoto.url;

      await _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync current patient profile notice: $e');
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
      if (!_isAdminMode && !_isSubAdminMode) {
        _adminPatientReferrals.clear();
      }
      final allowedIds = _currentDoctorStrictIds();
      if (allowedIds.isNotEmpty) {
        _doctorReceivedPatientReferrals.removeWhere(
          (r) => r.doctorId.trim().isNotEmpty && !allowedIds.contains(r.doctorId.trim()),
        );
      }
      syncProblemRequestsFromApi();
      syncDoctorSharedRecordsFromApi();
    }
  }

  Future<void> syncProblemRequestsFromApi() async {
    try {
      final authUser = SupabaseService.safeCurrentUser;
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
        final category = (pr['problem_category'] ?? pr['problemCategory'] ?? 'Medical Consultation').toString();
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
          final matchingPatient = reqPatientId.isNotEmpty
              ? _allPatients.where((p) => p.id == reqPatientId && p.name.isNotEmpty).firstOrNull
              : null;
          pName = matchingPatient != null && matchingPatient.name.isNotEmpty
              ? matchingPatient.name
              : 'Patient';
          if (pPhone.isEmpty && matchingPatient != null) {
            pPhone = matchingPatient.phone;
          }
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
            problemDescription: (r.problemDescription.isNotEmpty && r.problemDescription != 'Scheduled dental consultation' && r.problemDescription != 'Scheduled medical consultation') ? r.problemDescription : existing.problemDescription,
            symptoms: r.symptoms.isNotEmpty ? r.symptoms : existing.symptoms,
            preferredLocation: r.preferredLocation.isNotEmpty ? r.preferredLocation : existing.preferredLocation,
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
      } else if (_safeAuthUserId != null) {
        targetDocId = _safeAuthUserId!;
      }

      if (targetDocId.isEmpty) {
        _dentistAssignedRequests.clear();
        notifyListeners();
        return;
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
        final category = (pr['problem_category'] ?? pr['problemCategory'] ?? 'Medical Consultation').toString();
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
            assignedDocName.isNotEmpty) {
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
          final matchingPatient = reqPatientId.isNotEmpty
              ? _allPatients.where((p) => p.id == reqPatientId && p.name.isNotEmpty).firstOrNull
              : null;
          pName = matchingPatient != null && matchingPatient.name.isNotEmpty
              ? matchingPatient.name
              : 'Patient';
          if (pPhone.isEmpty && matchingPatient != null) {
            pPhone = matchingPatient.phone;
          }
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
      final api = ApiService();
      final list = await api.fetchClinics();
      if (list.isEmpty && !api.lastFetchClinicsSucceeded) {
        return;
      }
      final seenIds = <String>{};
      final seenNames = <String>{};
      final freshClinics = <ClinicModel>[];
      for (final item in list) {
        if (item is! Map) continue;
        final model = ClinicModel.fromJson(Map<String, dynamic>.from(item));
        final idKey = model.id.trim();
        final nameLocKey = '${model.clinicName.trim().toLowerCase()}|${model.location.trim().toLowerCase()}';
        if (idKey.isNotEmpty && !seenIds.add(idKey)) continue;
        if (model.clinicName.trim().isNotEmpty && !seenNames.add(nameLocKey)) continue;
        freshClinics.add(model);
      }
      _allClinics
        ..clear()
        ..addAll(freshClinics);
      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync clinics error: $e');
    }
  }

  /// Return doctors belonging strictly to a specific clinic (matches clinicId first, then exact clinicName).
  List<DoctorModel> getDoctorsForClinic(ClinicModel clinic) {
    final cId = clinic.id.trim();
    final cUserId = clinic.userId.trim();
    final cName = clinic.clinicName.trim().toLowerCase();
    const genericPlaceholders = {
      '',
      'independent practice',
      'gs health partner clinic',
      'gs health medical center',
      'gs health practice',
      'gs health care clinic',
    };
    return _allDoctors.where((d) {
      final dClinicId = d.clinicId.trim();
      if (dClinicId.isNotEmpty) {
        return dClinicId == cId || (cUserId.isNotEmpty && dClinicId == cUserId);
      }
      final dCName = d.clinicName.trim().toLowerCase();
      if (cName.isNotEmpty && !genericPlaceholders.contains(dCName) && dCName == cName) {
        return true;
      }
      return false;
    }).toList();
  }

  /// Fetch latest doctors for a specific clinic from backend API and refresh cache.
  Future<List<DoctorModel>> fetchClinicDoctors(ClinicModel clinic) async {
    try {
      final rawList = await ApiService().fetchClinicDentists(clinic.id, includeUnavailable: true);
      if (rawList.isNotEmpty) {
        final fetchedDocs = <DoctorModel>[];
        for (final item in rawList) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            if ((map['clinic_id'] ?? map['clinicId'] ?? '').toString().trim().isEmpty) {
              map['clinic_id'] = clinic.id;
            }
            if ((map['clinicName'] ?? '').toString().trim().isEmpty) {
              map['clinicName'] = clinic.clinicName;
            }
            final parsed = DoctorModel.fromJson(map);
            fetchedDocs.add(parsed);
            final idx = _allDoctors.indexWhere((d) =>
                (d.id.isNotEmpty && d.id == parsed.id) ||
                (d.userId.isNotEmpty && d.userId == parsed.userId));
            if (idx >= 0) {
              _allDoctors[idx] = parsed;
            } else {
              _allDoctors.add(parsed);
            }
          }
        }
        _saveToStorage();
        notifyListeners();
        return fetchedDocs;
      }
    } catch (e) {
      debugPrint('Fetch clinic doctors error: $e');
    }
    return getDoctorsForClinic(clinic);
  }

  /// Associate an existing registered doctor to a clinic without deleting or duplicating accounts.
  Future<bool> associateDoctorToClinic({
    required ClinicModel clinic,
    required DoctorModel doctor,
  }) async {
    final docKey = doctor.id.isNotEmpty ? doctor.id : doctor.userId;
    final ok = await ApiService().associateClinicDoctorApi(
      clinicId: clinic.id,
      doctorId: docKey,
      clinicName: clinic.clinicName,
      specialty: doctor.specialty,
    );
    if (ok) {
      final idx = _allDoctors.indexWhere((d) => d.id == doctor.id || (doctor.userId.isNotEmpty && d.userId == doctor.userId));
      if (idx >= 0) {
        final existing = _allDoctors[idx];
        _allDoctors[idx] = DoctorModel(
          id: existing.id,
          userId: existing.userId,
          clinicId: clinic.id,
          name: existing.name,
          specialty: existing.specialty,
          qualification: existing.qualification,
          experienceYears: existing.experienceYears,
          rating: existing.rating,
          reviewCount: existing.reviewCount,
          clinicName: clinic.clinicName,
          phone: existing.phone,
          email: existing.email,
          status: existing.status,
          verificationStatus: existing.verificationStatus,
          nextAvailableSlots: existing.nextAvailableSlots,
          consultationFee: existing.consultationFee,
          licenseNumber: existing.licenseNumber,
          photoBytes: existing.photoBytes,
          clinicAddress: clinic.location,
          pincode: existing.pincode,
          city: existing.city,
          state: existing.state,
          bio: existing.bio,
          languages: existing.languages,
          latitude: existing.latitude,
          longitude: existing.longitude,
          procedureFees: existing.procedureFees,
        );
      }
      _saveToStorage();
      notifyListeners();
    }
    return ok;
  }

  /// Remove doctor from a clinic without deleting the doctor's global profile or patient records.
  Future<bool> removeDoctorFromClinicAssociation({
    required ClinicModel clinic,
    required DoctorModel doctor,
  }) async {
    final docKey = doctor.id.isNotEmpty ? doctor.id : doctor.userId;
    final ok = await ApiService().removeDoctorFromClinicApi(
      clinicId: clinic.id,
      doctorId: docKey,
    );
    if (ok) {
      final idx = _allDoctors.indexWhere((d) => d.id == doctor.id || (doctor.userId.isNotEmpty && d.userId == doctor.userId));
      if (idx >= 0) {
        final existing = _allDoctors[idx];
        _allDoctors[idx] = DoctorModel(
          id: existing.id,
          userId: existing.userId,
          clinicId: '',
          name: existing.name,
          specialty: existing.specialty,
          qualification: existing.qualification,
          experienceYears: existing.experienceYears,
          rating: existing.rating,
          reviewCount: existing.reviewCount,
          clinicName: '',
          phone: existing.phone,
          email: existing.email,
          status: existing.status,
          verificationStatus: existing.verificationStatus,
          nextAvailableSlots: existing.nextAvailableSlots,
          consultationFee: existing.consultationFee,
          licenseNumber: existing.licenseNumber,
          photoBytes: existing.photoBytes,
          clinicAddress: '',
          pincode: existing.pincode,
          city: existing.city,
          state: existing.state,
          bio: existing.bio,
          languages: existing.languages,
          latitude: existing.latitude,
          longitude: existing.longitude,
          procedureFees: existing.procedureFees,
        );
      }
      _saveToStorage();
      notifyListeners();
    }
    return ok;
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

  static List<String> _parseLangRawList(dynamic rawLangs) {
    return ApiService.deduplicateLanguages(rawLangs);
  }

  static List<String> _extractDoctorLanguages(Map<dynamic, dynamic> dMap, Map<dynamic, dynamic> userObj) {
    final dLangs = _parseLangRawList(dMap['languages']);
    final uLangs = _parseLangRawList(userObj['languages']);
    List<String> metaLangs = [];
    final devToken = userObj['device_token']?.toString() ?? '';
    if (devToken.startsWith('{')) {
      try {
        final meta = jsonDecode(devToken);
        if (meta is Map && meta['languages'] != null) {
          metaLangs = _parseLangRawList(meta['languages']);
        }
      } catch (_) {}
    }

    if (dLangs.length > 1 || (dLangs.length == 1 && dLangs.first.toLowerCase() != 'english')) {
      return dLangs;
    }
    if (uLangs.length > 1 || (uLangs.length == 1 && uLangs.first.toLowerCase() != 'english')) {
      return uLangs;
    }
    if (metaLangs.isNotEmpty) {
      return metaLangs;
    }
    if (dLangs.isNotEmpty) return dLangs;
    if (uLangs.isNotEmpty) return uLangs;
    return const ['English'];
  }

  Future<void> syncDoctorsFromApi({bool? includeUnavailable}) async {
    try {
      final shouldIncludeUnavailable = includeUnavailable ?? true;
      final api = ApiService();
      final apiDentists = await api.fetchDentists(includeUnavailable: shouldIncludeUnavailable);
      if (apiDentists.isNotEmpty || api.lastFetchDentistsSucceeded) {
        final seenIds = <String>{};
        final seenUserIds = <String>{};
        final seenEmails = <String>{};
        final seenPhones = <String>{};
        final freshDoctors = <DoctorModel>[];
        for (final dMap in apiDentists) {
          if (dMap is! Map) continue;
          final id = dMap['id']?.toString().trim() ?? dMap['_id']?.toString().trim() ?? '';
          final userObj = dMap['users'] ?? dMap['user'] ?? {};
          final clinicObj = dMap['clinics'] ?? dMap['clinic'] ?? {};
          
          var rawName = (userObj['name'] ?? dMap['name'] ?? dMap['dentist_name'] ?? '').toString().trim();
          if (rawName.isEmpty || rawName.toLowerCase() == 'dentist' || rawName == 'Dr.') {
            final cNameStr = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString().trim();
            if (cNameStr.isNotEmpty) {
              rawName = cNameStr;
            } else {
              rawName = 'Medical Doctor';
            }
          }
          final formattedName = rawName.startsWith('Dr.') ? rawName : 'Dr. $rawName';
          final email = (userObj['email'] ?? dMap['email'] ?? '').toString().trim();
          final phone = (userObj['phone'] ?? dMap['phone'] ?? '').toString().trim();
          final rawSpec = (dMap['speciality'] ?? dMap['specialty'] ?? '').toString().trim();
          final specialty = rawSpec.isNotEmpty ? rawSpec : 'General Medicine';
          final licNum = (dMap['license_number'] ?? dMap['licenseNumber'] ?? '').toString();
          final resolvedClinicId = (dMap['clinic_id'] ?? dMap['clinicId'] ?? clinicObj['id'] ?? '').toString().trim();
          final cName = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString();
          final cLoc = (clinicObj['location'] ?? dMap['location'] ?? '').toString();
          final docBio = (dMap['bio'] ?? dMap['about'] ?? dMap['description'] ?? userObj['bio'] ?? '').toString();

          final doctorState = (dMap['state'] ?? userObj['state'] ?? '').toString();
          final doctorCity = (dMap['city'] ?? userObj['city'] ?? '').toString();
          final doctorPincode = (dMap['pincode'] ?? userObj['pincode'] ?? dMap['postal_code'] ?? '').toString();
          final lat = (dMap['latitude'] ?? userObj['latitude']) != null ? double.tryParse((dMap['latitude'] ?? userObj['latitude']).toString()) : null;
          final lng = (dMap['longitude'] ?? userObj['longitude']) != null ? double.tryParse((dMap['longitude'] ?? userObj['longitude']).toString()) : null;

          final List<String> doctorLangs = _extractDoctorLanguages(
            dMap,
            userObj is Map ? userObj : <String, dynamic>{},
          );

          final doctorUserId = (dMap['user_id'] ?? userObj['id'] ?? '').toString().trim();

          final emailLower = email.toLowerCase();
          final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
          final phone10 = phoneDigits.length >= 10
              ? phoneDigits.substring(phoneDigits.length - 10)
              : phoneDigits;
          if (id.isNotEmpty && !seenIds.add(id)) continue;
          if (doctorUserId.isNotEmpty && !seenUserIds.add(doctorUserId)) continue;
          if (emailLower.isNotEmpty && !seenEmails.add(emailLower)) continue;
          if (phone10.length >= 10 && !seenPhones.add(phone10)) continue;

          final parsedPhoto = DoctorModel.parseProfilePhoto(
            userObj['biometric_token'] ??
                dMap['profilePhoto'] ??
                dMap['profile_photo'] ??
                dMap['profileImageUrl'] ??
                dMap['photo'] ??
                dMap['avatar'] ??
                userObj['avatar'] ??
                '',
          );
          final Uint8List? docPhotoBytes = parsedPhoto.bytes;
          final String? docPhotoUrl = parsedPhoto.url;

          final rawSlots = dMap['slots'] ?? dMap['available_slots'] ?? dMap['nextAvailableSlots'];
          final List<String> parsedSlots = rawSlots is List
              ? rawSlots.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList()
              : <String>[];

          final parsedQual = (dMap['qualifications'] ?? dMap['qualification'] ?? '').toString().trim();

          freshDoctors.add(DoctorModel(
            id: id.isNotEmpty ? id : 'DOC-${100 + freshDoctors.length + 1}',
            userId: doctorUserId,
            clinicId: resolvedClinicId,
            name: formattedName,
            specialty: specialty,
            qualification: parsedQual.isNotEmpty
                ? parsedQual
                : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(specialty),
            experienceYears: int.tryParse((dMap['experience_years'] ?? dMap['experienceYears'] ?? '0').toString()) ?? 0,
            rating: (dMap['rating'] ?? 5.0).toDouble(),
            reviewCount: dMap['reviews_count'] ?? 0,
            clinicName: cName,
            clinicAddress: cLoc,
            phone: phone,
            email: email,
            status: (dMap['availability_status'] ?? dMap['status'] ?? 'Available').toString(),
            onlineStatus: (dMap['onlineStatus'] ?? dMap['online_status'] ?? '').toString(),
            verificationStatus: (dMap['verificationStatus'] ?? dMap['verification_status'] ?? 'VERIFIED').toString(),
            nextAvailableSlots: parsedSlots,
            consultationFee: (dMap['consultation_fee'] ?? dMap['consultationFee'] ?? '').toString(),
            licenseNumber: licNum,
            photoBytes: docPhotoBytes,
            profileImageUrl: docPhotoUrl,
            state: doctorState,
            city: doctorCity,
            pincode: doctorPincode,
            bio: docBio,
            languages: doctorLangs,
            latitude: lat,
            longitude: lng,
          ));
        }
        _allDoctors
          ..clear()
          ..addAll(freshDoctors);
      }
      final authUser = SupabaseService.safeCurrentUser;
      if (authUser != null && authUser.email != null && authUser.email!.isNotEmpty) {
        final authEmailLower = authUser.email!.toLowerCase();
        final authName = (authUser.userMetadata?['name'] ?? '').toString().replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
        for (final d in _allDoctors) {
          final dNameClean = d.name.replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
          if (d.email.toLowerCase() == authEmailLower ||
              (d.id.isNotEmpty && d.id == authUser.id) ||
              (d.userId.isNotEmpty && d.userId == authUser.id) ||
              (authName.isNotEmpty && dNameClean == authName)) {
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

  /// Fetch doctors from API filtered by state, city, pincode, specialty, availability, language, search.
  /// Returns filtered list without modifying the global [_allDoctors] cache.
  Future<List<DoctorModel>> fetchDoctorsFiltered({
    String? state,
    String? city,
    String? pincode,
    String? specialty,
    String? availability,
    String? language,
    List<String>? languages,
    String? search,
    bool includeUnavailable = false,
  }) async {
    try {
      final apiDentists = await ApiService().fetchDentists(
        state: state,
        city: city,
        pincode: pincode,
        specialty: specialty,
        availability: availability,
        language: language,
        languages: languages,
        search: search,
        includeUnavailable: includeUnavailable,
      );
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
        final docBio = (dMap['bio'] ?? dMap['about'] ?? dMap['description'] ?? userObj['bio'] ?? '').toString();
        final doctorState = (dMap['state'] ?? userObj['state'] ?? '').toString();
        final doctorCity = (dMap['city'] ?? userObj['city'] ?? '').toString();
        final doctorPincode = (dMap['pincode'] ?? userObj['pincode'] ?? dMap['postal_code'] ?? '').toString();
        final lat = (dMap['latitude'] ?? userObj['latitude']) != null ? double.tryParse((dMap['latitude'] ?? userObj['latitude']).toString()) : null;
        final lng = (dMap['longitude'] ?? userObj['longitude']) != null ? double.tryParse((dMap['longitude'] ?? userObj['longitude']).toString()) : null;
        final doctorUserId = (dMap['user_id'] ?? userObj['id'] ?? '').toString();

        final parsedPhoto = DoctorModel.parseProfilePhoto(
          userObj['biometric_token'] ??
              dMap['profilePhoto'] ??
              dMap['profile_photo'] ??
              dMap['profileImageUrl'] ??
              dMap['photo'] ??
              dMap['avatar'] ??
              userObj['avatar'] ??
              '',
        );
        final Uint8List? docPhotoBytes = parsedPhoto.bytes;
        final String? docPhotoUrl = parsedPhoto.url;

        final rawSlots = dMap['slots'] ?? dMap['available_slots'] ?? dMap['nextAvailableSlots'];
        final List<String> parsedSlots = rawSlots is List
            ? rawSlots.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList()
            : <String>[];

        final List<String> doctorLangs = _extractDoctorLanguages(
          dMap is Map ? dMap : <String, dynamic>{},
          userObj is Map ? userObj : <String, dynamic>{},
        );

        final formattedName = name.startsWith('Dr.') ? name : 'Dr. $name';
        final resolvedClinicId = (dMap['clinic_id'] ?? dMap['clinicId'] ?? clinicObj['id'] ?? '').toString().trim();
        final parsedQual = (dMap['qualifications'] ?? dMap['qualification'] ?? '').toString().trim();

        filtered.add(DoctorModel(
          id: id.isNotEmpty ? id : 'DOC-${filtered.length + 1}',
          userId: doctorUserId,
          clinicId: resolvedClinicId,
          name: formattedName,
          specialty: spec,
          qualification: parsedQual.isNotEmpty
              ? parsedQual
              : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(spec),
          experienceYears: int.tryParse((dMap['experience_years'] ?? dMap['experienceYears'] ?? '0').toString()) ?? 0,
          rating: (dMap['rating'] ?? 5.0).toDouble(),
          reviewCount: dMap['reviews_count'] ?? 0,
          clinicName: cName,
          clinicAddress: cLoc,
          phone: phone,
          email: email,
          status: (dMap['availability_status'] ?? dMap['status'] ?? 'Available').toString(),
          onlineStatus: (dMap['onlineStatus'] ?? dMap['online_status'] ?? '').toString(),
          verificationStatus: (dMap['verificationStatus'] ?? dMap['verification_status'] ?? 'VERIFIED').toString(),
          nextAvailableSlots: parsedSlots,
          consultationFee: (dMap['consultation_fee'] ?? dMap['consultationFee'] ?? '').toString(),
          licenseNumber: licNum,
          photoBytes: docPhotoBytes,
          profileImageUrl: docPhotoUrl,
          state: doctorState,
          city: doctorCity,
          pincode: doctorPincode,
          bio: docBio,
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
      final sess = SessionService().currentSession;
      final sessRoleLower = (sess?.role ?? '').trim().toLowerCase();
      final isClinicSession = _isClinicMode || sessRoleLower.contains('clinic');
      final pId = currentPatient.id.isNotEmpty
          ? currentPatient.id
          : (sessRoleLower == 'patient' && (sess?.userId.isNotEmpty ?? false)
              ? sess!.userId
              : (!isClinicSession && !_isDentistMode ? _safeAuthUserId : null));

      // Build complete set of doctor identifiers (both dentists.id and users.id) for the logged-in doctor
      final myDoctorIds = <String>{};
      if (currentDoctor != null) {
        if (currentDoctor!.id.isNotEmpty) myDoctorIds.add(currentDoctor!.id);
        if (currentDoctor!.userId.isNotEmpty) myDoctorIds.add(currentDoctor!.userId);
      }
      if ((_isDentistMode || sessRoleLower == 'dentist' || sessRoleLower == 'doctor') &&
          (sess?.userId.isNotEmpty ?? false)) {
        myDoctorIds.add(sess!.userId);
      }
      if (_isDentistMode && (_safeAuthUserId?.isNotEmpty ?? false)) {
        myDoctorIds.add(_safeAuthUserId!);
      }
      for (final d in _allDoctors) {
        final emailMatches = currentDoctor != null &&
            currentDoctor!.email.isNotEmpty &&
            d.email.isNotEmpty &&
            d.email.toLowerCase() == currentDoctor!.email.toLowerCase();
        final phoneMatches = currentDoctor != null &&
            currentDoctor!.phone.isNotEmpty &&
            d.phone.isNotEmpty &&
            d.phone.replaceAll(RegExp(r'\D'), '') ==
                currentDoctor!.phone.replaceAll(RegExp(r'\D'), '');
        final idMatches = myDoctorIds.contains(d.id) ||
            (d.userId.isNotEmpty && myDoctorIds.contains(d.userId));
        if (idMatches || emailMatches || phoneMatches) {
          if (d.id.isNotEmpty) myDoctorIds.add(d.id);
          if (d.userId.isNotEmpty) myDoctorIds.add(d.userId);
          // Upgrade currentDoctor.id to dentists.id if it was set to users.id at login
          if (currentDoctor != null && d.id.isNotEmpty && currentDoctor!.id != d.id) {
            currentDoctor = DoctorModel(
              id: d.id,
              userId: d.userId.isNotEmpty ? d.userId : currentDoctor!.id,
              name: currentDoctor!.name.isNotEmpty ? currentDoctor!.name : d.name,
              specialty: currentDoctor!.specialty.isNotEmpty ? currentDoctor!.specialty : d.specialty,
              qualification: currentDoctor!.qualification.isNotEmpty ? currentDoctor!.qualification : d.qualification,
              experienceYears: currentDoctor!.experienceYears,
              rating: currentDoctor!.rating,
              reviewCount: currentDoctor!.reviewCount,
              clinicName: currentDoctor!.clinicName.isNotEmpty ? currentDoctor!.clinicName : d.clinicName,
              phone: currentDoctor!.phone.isNotEmpty ? currentDoctor!.phone : d.phone,
              email: currentDoctor!.email.isNotEmpty ? currentDoctor!.email : d.email,
              status: d.status.isNotEmpty ? d.status : currentDoctor!.status,
              verificationStatus: d.verificationStatus,
              nextAvailableSlots: currentDoctor!.nextAvailableSlots,
              consultationFee: currentDoctor!.consultationFee,
              licenseNumber: currentDoctor!.licenseNumber,
              photoBytes: currentDoctor!.photoBytes ?? d.photoBytes,
              profileImageUrl: currentDoctor!.profileImageUrl ?? d.profileImageUrl,
              clinicAddress: currentDoctor!.clinicAddress.isNotEmpty ? currentDoctor!.clinicAddress : d.clinicAddress,
              pincode: currentDoctor!.pincode.isNotEmpty ? currentDoctor!.pincode : d.pincode,
              city: currentDoctor!.city.isNotEmpty ? currentDoctor!.city : d.city,
              state: currentDoctor!.state.isNotEmpty ? currentDoctor!.state : d.state,
              bio: currentDoctor!.bio.isNotEmpty ? currentDoctor!.bio : d.bio,
              languages: currentDoctor!.languages.isNotEmpty ? currentDoctor!.languages : d.languages,
            );
          }
        }
      }

      final String? dId = currentDoctor?.id.isNotEmpty == true
          ? currentDoctor!.id
          : (currentDoctor?.userId.isNotEmpty == true
              ? currentDoctor!.userId
              : (myDoctorIds.isNotEmpty ? myDoctorIds.first : null));

      final String? cId = isClinicSession
          ? (_authenticatedClinicId.isNotEmpty
              ? _authenticatedClinicId
              : (resolveClinic()?.id.isNotEmpty == true
                  ? resolveClinic()!.id
                  : ((sess?.userId.isNotEmpty ?? false)
                      ? sess!.userId
                      : (_authenticatedClinicName.isNotEmpty ? _authenticatedClinicName : _safeAuthUserId))))
          : null;

      final list = _isDentistMode
          ? (dId != null ? await _api.fetchAppointments(dentistId: dId) : <dynamic>[])
          : (isClinicSession
              ? (cId != null && cId.isNotEmpty ? await _api.fetchAppointments(clinicId: cId) : <dynamic>[])
              : (pId != null ? await _api.fetchAppointments(patientId: pId) : <dynamic>[]));

      if (list.isEmpty) {
        if (_isDentistMode && myDoctorIds.isNotEmpty) {
          // Strict doctor isolation: purge any cached entries belonging to other doctors
          // without wiping the logged-in doctor's own appointments on temporary offline/empty responses.
          _requests.removeWhere((r) {
            final aId = (r.assignedDoctorId ?? '').trim();
            return aId.isNotEmpty && !myDoctorIds.contains(aId);
          });
          _saveToStorage();
          notifyListeners();
        }
        return;
      }

      for (final item in list) {
        if (item is! Map) continue;
        final itemPatientId = (item['patient_id'] ?? item['patientId'] ?? item['patient']?['id'])?.toString();
        final selectedDocMap = item['selectedDoctor'] is Map ? Map<String, dynamic>.from(item['selectedDoctor']) : <String, dynamic>{};
        final dentistMap = item['dentist'] is Map ? Map<String, dynamic>.from(item['dentist']) : <String, dynamic>{};
        final dentistUserMap = dentistMap['users'] is Map ? Map<String, dynamic>.from(dentistMap['users']) : <String, dynamic>{};
        final dentistClinicMap = dentistMap['clinics'] is Map ? Map<String, dynamic>.from(dentistMap['clinics']) : <String, dynamic>{};
        final itemDentistId = (item['dentist_id'] ?? item['dentistId'] ?? selectedDocMap['id'] ?? dentistMap['id'])?.toString();
        final itemDentistUserId = (selectedDocMap['user_id'] ?? dentistMap['user_id'] ?? dentistUserMap['id'])?.toString();

        final authUser = SupabaseService.safeCurrentUser;
        final isAdmin = _isAdminMode ||
            _isSubAdminMode ||
            (authUser?.email != null && authUser!.email!.toLowerCase().contains('admin')) ||
            currentPatient.email.toLowerCase().contains('admin');

        if (_isDentistMode && myDoctorIds.isNotEmpty) {
          final matchesId = (itemDentistId != null && itemDentistId.isNotEmpty && myDoctorIds.contains(itemDentistId)) ||
              (itemDentistUserId != null && itemDentistUserId.isNotEmpty && myDoctorIds.contains(itemDentistUserId));
          if (!matchesId) {
            continue; // Strict doctor isolation: skip unassigned or other doctors' appointments
          }
        }

        if (!isAdmin &&
            !_isDentistMode &&
            !isClinicSession &&
            pId != null &&
            pId.isNotEmpty &&
            itemPatientId != null &&
            itemPatientId.isNotEmpty &&
            itemPatientId != pId &&
            !itemPatientId.contains(pId)) {
          continue; // Skip appointments belonging to another patient
        }

        final reqId = (item['_id'] ?? item['id'] ?? 'REQ-${item['patient_id']}-${DateTime.now().millisecondsSinceEpoch}').toString();

        final patientObj = item['patient'] is Map
            ? Map<String, dynamic>.from(item['patient'])
            : (item['users'] is Map ? Map<String, dynamic>.from(item['users']) : <String, dynamic>{});
        final String rawPName = (patientObj['name'] ?? item['patient_name'] ?? item['patientName'] ?? '').toString().trim();
        final String pName = (rawPName.isNotEmpty && rawPName != 'Patient')
            ? rawPName
            : (currentPatient.name.isNotEmpty ? currentPatient.name : 'Patient Consultation');

        final String pPhone = (patientObj['phone'] ?? item['patient_phone'] ?? item['phone'] ?? (currentPatient.phone.isNotEmpty ? currentPatient.phone : '')).toString().trim();
        final String pEmail = (patientObj['email'] ?? item['patient_email'] ?? '').toString().trim();
        final String pCity = (patientObj['city'] ?? item['patient_city'] ?? currentPatient.city).toString().trim();
        final String pPincode = (patientObj['pincode'] ?? item['patient_pincode'] ?? currentPatient.pincode).toString().trim();
        final String pAge = (patientObj['age'] ?? item['patient_age'] ?? '').toString().trim();
        final String pGender = (patientObj['gender'] ?? item['patient_gender'] ?? '').toString().trim();
        final String pBloodGroup = (patientObj['bloodGroup'] ?? patientObj['blood_group'] ?? '').toString().trim();

        final isDoctorOrStaffAccount = (itemPatientId != null && itemPatientId.isNotEmpty && (
            _allDoctors.any((d) => d.id == itemPatientId || d.userId == itemPatientId) ||
            _subAdmins.any((s) => (s['id'] ?? '').toString() == itemPatientId)
        )) || (pEmail.isNotEmpty && (
            _allDoctors.any((d) => d.email.isNotEmpty && d.email.toLowerCase() == pEmail.toLowerCase()) ||
            pEmail.toLowerCase().contains('admin')
        )) || pName.toLowerCase().startsWith('dr.');

        if (!isDoctorOrStaffAccount &&
            ((itemPatientId != null && itemPatientId.isNotEmpty) || (pName.isNotEmpty && pName != 'Patient Consultation'))) {
          final existingPatIdx = _allPatients.indexWhere(
            (p) =>
                (itemPatientId != null && itemPatientId.isNotEmpty && p.id == itemPatientId) ||
                (pPhone.isNotEmpty && p.phone == pPhone) ||
                (pEmail.isNotEmpty && p.email.isNotEmpty && p.email.toLowerCase() == pEmail.toLowerCase()) ||
                (pName.isNotEmpty && p.name.trim().toLowerCase() == pName.trim().toLowerCase()),
          );
          if (existingPatIdx != -1) {
            final ep = _allPatients[existingPatIdx];
            if (pPhone.isNotEmpty && ep.phone.isEmpty) ep.phone = pPhone;
            if (pEmail.isNotEmpty && ep.email.isEmpty) ep.email = pEmail;
            if (pCity.isNotEmpty && ep.city.isEmpty) ep.city = pCity;
            if (pPincode.isNotEmpty && ep.pincode.isEmpty) ep.pincode = pPincode;
            if (pAge.isNotEmpty && ep.age.isEmpty) ep.age = pAge;
            if (pGender.isNotEmpty && ep.gender.isEmpty) ep.gender = pGender;
            if (pBloodGroup.isNotEmpty && ep.bloodGroup.isEmpty) ep.bloodGroup = pBloodGroup;
          } else if (itemPatientId != null && itemPatientId.isNotEmpty) {
            _allPatients.add(
              PatientProfile(
                id: itemPatientId,
                name: pName,
                phone: pPhone,
                email: pEmail,
                city: pCity,
                pincode: pPincode,
                age: pAge,
                gender: pGender,
                bloodGroup: pBloodGroup,
              ),
            );
          }
        }

        DoctorModel? matchedDoc;
        if (itemDentistId != null && itemDentistId.isNotEmpty) {
          matchedDoc = _allDoctors
              .where((d) =>
                  d.id == itemDentistId ||
                  d.userId == itemDentistId ||
                  (itemDentistUserId != null && (d.id == itemDentistUserId || d.userId == itemDentistUserId)))
              .firstOrNull;
        }

        String rawDocName = (
          selectedDocMap['name'] ??
          item['dentist_name'] ??
          item['dentistName'] ??
          dentistUserMap['name'] ??
          dentistMap['name'] ??
          matchedDoc?.name ??
          ''
        ).toString().trim();
        String? assignedDocName;
        if (rawDocName.isNotEmpty && rawDocName != 'null') {
          assignedDocName = (rawDocName.toLowerCase().startsWith('dr.') || rawDocName.toLowerCase().startsWith('dr '))
              ? rawDocName
              : 'Dr. $rawDocName';
        }

        final String resolvedSpecialty = (
          selectedDocMap['specialty'] ??
          item['doctor_specialty'] ??
          dentistMap['speciality'] ??
          dentistMap['specialty'] ??
          matchedDoc?.specialty ??
          ''
        ).toString().trim();

        final clinicObj = item['clinic'] is Map ? Map<String, dynamic>.from(item['clinic']) : <String, dynamic>{};
        final clinic = (
          selectedDocMap['clinicName'] ??
          clinicObj['clinic_name'] ??
          clinicObj['name'] ??
          dentistClinicMap['clinic_name'] ??
          dentistClinicMap['name'] ??
          item['clinic_name'] ??
          item['clinicName'] ??
          matchedDoc?.clinicName ??
          ''
        ).toString().trim();

        final treatment = (item['treatment'] ?? 'Medical Consultation').toString().trim();
        final slot = item['time_slot'] ?? item['timeSlot'];
        final rawDate = (item['date'] ?? item['appointment_date'] ?? item['appointmentDate'])?.toString();
        final statusStr = (item['status'] ?? 'PENDING').toString();
        final rawCreatedAt = (item['booking_created_at'] ?? item['created_at'])?.toString();
        final parsedCreatedAt = rawCreatedAt != null ? DateTime.tryParse(rawCreatedAt) : null;

        final String referralSource = (item['referral_source'] ?? '').toString().trim();
        final String effectiveNotes = referralSource.isNotEmpty
            ? 'Referral Source: $referralSource'
            : (item['referral_id'] != null ? 'Referral Consultation' : 'Consultation record');
        final String effectiveDesc = referralSource.isNotEmpty
            ? 'Referred by $referralSource'
            : 'Scheduled medical consultation';

        final normalizedRawDate = (rawDate ?? '').split('T').first.trim();
        final existingIndex = _requests.indexWhere((r) {
          if (r.id == reqId) return true;
          final rIsSynthetic = r.id.startsWith('PR-') || r.id.startsWith('REQ-');
          if (!rIsSynthetic) return false;
          final rDateNorm = (r.confirmedDate ?? '').split('T').first.trim();
          final dateMatches = normalizedRawDate.isEmpty || rDateNorm.isEmpty || rDateNorm == normalizedRawDate;
          final docMatches = itemDentistId == null ||
              itemDentistId.isEmpty ||
              r.assignedDoctorId == null ||
              r.assignedDoctorId!.isEmpty ||
              r.assignedDoctorId == itemDentistId;
          return itemPatientId != null &&
              itemPatientId.isNotEmpty &&
              r.patientId != null &&
              r.patientId == itemPatientId &&
              r.problemCategory.trim().toLowerCase() == treatment.toLowerCase() &&
              r.confirmedTimeSlot == slot?.toString() &&
              dateMatches &&
              docMatches;
        });

        final String? parsedMode = (item['consultationMode'] ?? item['consultation_type'])?.toString().trim();
        final String? parsedEndTime = (item['scheduledEndTime'] ?? item['scheduled_end_time'])?.toString().trim();
        final String? parsedBufEnd = (item['bufferEndTime'] ?? item['buffer_end_time'])?.toString().trim();
        final int? parsedDurMins = int.tryParse((item['durationMinutes'] ?? item['duration_minutes'] ?? '').toString());
        final int? parsedBufMins = int.tryParse((item['bufferMinutes'] ?? item['buffer_minutes'] ?? '').toString());
        final String? parsedActStart = (item['actualStartAt'] ?? item['actual_start_at'])?.toString();
        final String? parsedActEnd = (item['actualEndAt'] ?? item['actual_end_at'])?.toString();
        final int parsedDelayMins = int.tryParse((item['delayMinutes'] ?? item['delay_minutes'] ?? '0').toString()) ?? 0;
        final String? parsedEstStart = (item['estimatedStartTime'] ?? item['estimated_start_time'])?.toString();
        final reschedReqMap = item['reschedule_request'] is Map ? item['reschedule_request'] as Map : const {};
        final String? parsedReschedStatus = reschedReqMap['status']?.toString();
        final String? parsedReschedDate = reschedReqMap['requestedDate']?.toString();
        final String? parsedReschedSlot = reschedReqMap['requestedTimeSlot']?.toString();
        final String? parsedReschedReason = reschedReqMap['reason']?.toString();
        final String? parsedDelayChoice = item['patient_delay_choice']?.toString();

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
          if (resolvedSpecialty.isNotEmpty) {
            _requests[existingIndex].assignedDoctorSpecialty = resolvedSpecialty;
          }
          if (itemDentistId != null && itemDentistId.isNotEmpty) {
            _requests[existingIndex].assignedDoctorId = itemDentistId;
          }
          _requests[existingIndex].status = statusStr;
          if (clinic.isNotEmpty) {
            _requests[existingIndex].assignedDoctorClinic = clinic;
          }
          if (parsedMode != null && parsedMode.isNotEmpty) _requests[existingIndex].consultationMode = parsedMode;
          if (parsedEndTime != null && parsedEndTime.isNotEmpty) _requests[existingIndex].scheduledEndTime = parsedEndTime;
          if (parsedBufEnd != null && parsedBufEnd.isNotEmpty) _requests[existingIndex].bufferEndTime = parsedBufEnd;
          if (parsedDurMins != null) _requests[existingIndex].durationMinutes = parsedDurMins;
          if (parsedBufMins != null) _requests[existingIndex].bufferMinutes = parsedBufMins;
          if (parsedActStart != null) _requests[existingIndex].actualStartAt = parsedActStart;
          if (parsedActEnd != null) _requests[existingIndex].actualEndAt = parsedActEnd;
          _requests[existingIndex].delayMinutes = parsedDelayMins;
          _requests[existingIndex].estimatedStartTime = parsedEstStart;
          _requests[existingIndex].rescheduleRequestStatus = parsedReschedStatus;
          _requests[existingIndex].rescheduleRequestedDate = parsedReschedDate;
          _requests[existingIndex].rescheduleRequestedSlot = parsedReschedSlot;
          _requests[existingIndex].rescheduleRequestReason = parsedReschedReason;
          _requests[existingIndex].patientDelayChoice = parsedDelayChoice;
        } else {
          _requests.add(
            PatientConsultationRequest(
              id: reqId,
              patientId: itemPatientId,
              patientName: pName,
              patientPhone: pPhone,
              problemCategory: treatment,
              problemDescription: effectiveDesc,
              severity: 'Moderate',
              submittedAt: parsedCreatedAt ?? DateTime.now(),
              status: statusStr,
              assignedDoctorId: itemDentistId ?? dId,
              assignedDoctorName: assignedDocName,
              assignedDoctorSpecialty: resolvedSpecialty.isNotEmpty ? resolvedSpecialty : 'General Dentistry',
              assignedDoctorClinic: clinic.isNotEmpty ? clinic : 'GS HEALTH Practice',
              confirmedTimeSlot: slot?.toString(),
              confirmedDate: rawDate,
              city: pCity,
              pincode: pPincode,
              adminNotes: effectiveNotes,
              whatsappNotificationSent: true,
              consultationMode: parsedMode,
              scheduledEndTime: parsedEndTime,
              bufferEndTime: parsedBufEnd,
              durationMinutes: parsedDurMins,
              bufferMinutes: parsedBufMins,
              actualStartAt: parsedActStart,
              actualEndAt: parsedActEnd,
              delayMinutes: parsedDelayMins,
              estimatedStartTime: parsedEstStart,
              rescheduleRequestStatus: parsedReschedStatus,
              rescheduleRequestedDate: parsedReschedDate,
              rescheduleRequestedSlot: parsedReschedSlot,
              rescheduleRequestReason: parsedReschedReason,
              patientDelayChoice: parsedDelayChoice,
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
            problemDescription: (r.problemDescription.isNotEmpty && r.problemDescription != 'Scheduled dental consultation' && r.problemDescription != 'Scheduled medical consultation') ? r.problemDescription : existing.problemDescription,
            symptoms: r.symptoms.isNotEmpty ? r.symptoms : existing.symptoms,
            preferredLocation: r.preferredLocation.isNotEmpty ? r.preferredLocation : existing.preferredLocation,
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

  /// Book a new appointment directly with selected doctor & time slot (supports mandatory lockId & releasedSlotId)
  Future<Map<String, dynamic>> bookAppointment({
    required String dentistId,
    String clinicId = '',
    required String date,
    required String timeSlot,
    required String treatment,
    String consultationMode = '',
    String symptoms = '',
    String? lockId,
    String? releasedSlotId,
    bool requireLock = false,
  }) async {
    final cleanDate = date.contains('T') ? date.split('T').first : date.trim();
    final cleanSlot = timeSlot.trim();
    if (dentistId.trim().isEmpty || cleanDate.isEmpty || cleanSlot.isEmpty) {
      return {
        'success': false,
        'message': 'Please select an available date and time slot.',
      };
    }

    final parsedDate = DateTime.tryParse(cleanDate);
    if (releasedSlotId == null && parsedDate != null && !BookingRulesConfig.isSlotBookableForDate(parsedDate, cleanSlot)) {
      return {
        'success': false,
        'message': 'Appointments must be booked at least ${BookingRulesConfig.minAdvanceBookingMinutes} minutes in advance and cannot use past slots.',
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

    // Prevent double booking (including duration + buffer overlap across Online/In-Person) in local state before submitting
    final reqMode = consultationMode.trim().isNotEmpty
        ? BookingRulesConfig.normalizeConsultationType(consultationMode)
        : BookingRulesConfig.normalizeConsultationType(treatment);
    final reqStartMin = BookingRulesConfig.parseSlotToMinutes(cleanSlot);
    final reqOccupiedMin = BookingRulesConfig.durationForType(reqMode) +
        BookingRulesConfig.bufferForType(reqMode);

    final alreadyBooked = _requests.any((req) {
      final matchesDoc = req.assignedDoctorId == dentistId ||
          (matchedDoc.id.isNotEmpty && req.assignedDoctorId == matchedDoc.id) ||
          (matchedDoc.userId.isNotEmpty && req.assignedDoctorId == matchedDoc.userId) ||
          (matchedDoc.name.isNotEmpty && req.assignedDoctorName == matchedDoc.name);
      if (!matchesDoc) return false;
      final s = req.status.toUpperCase();
      if (s == 'CANCELLED' || s == 'REJECTED' || s == 'NO_SHOW' || s == 'COMPLETED') return false;
      final rDate = req.confirmedDate?.split('T').first ?? req.submittedAt.toIso8601String().split('T').first;
      if (rDate != cleanDate) return false;
      final existingSlot = (req.confirmedTimeSlot ?? '').trim();
      if (existingSlot.toLowerCase() == cleanSlot.toLowerCase()) return true;
      final exStartMin = BookingRulesConfig.parseClockSlotMinutes(existingSlot);
      if (reqStartMin != null && exStartMin != null) {
        final exMode = BookingRulesConfig.normalizeConsultationMode(req.consultationMode ?? req.problemCategory);
        final exDur = req.durationMinutes ?? BookingRulesConfig.durationForMode(exMode);
        final exBuf = req.bufferMinutes ?? BookingRulesConfig.bufferForMode(exMode);
        final exDelay = req.delayMinutes;
        final exOccupied = exDur + exBuf + exDelay;
        return BookingRulesConfig.intervalsOverlap(
          reqStartMin,
          reqStartMin + reqOccupiedMin,
          exStartMin,
          exStartMin + exOccupied,
        );
      }
      return false;
    });

    final cachedAvail = _availabilityCache['${dentistId}_$cleanDate'];
    if (alreadyBooked ||
        (cachedAvail != null &&
            (cachedAvail.isBlocked ||
                cachedAvail.bookedSlots.any((b) => b.toLowerCase() == cleanSlot.toLowerCase()) ||
                cachedAvail.blockedSlots.any(
                  (b) => (b['startTime'] ?? b['slot'] ?? '').toString().toLowerCase() == cleanSlot.toLowerCase(),
                )))) {
      return {
        'success': false,
        'message': 'The selected time slot ($cleanSlot) is no longer available. Please choose another slot.',
      };
    }

    final pId = currentPatient.id.isNotEmpty
        ? currentPatient.id
        : (_safeAuthUserId ?? '');
    String effectiveClinicId = clinicId.trim();
    if (effectiveClinicId.isEmpty && matchedDoc.clinicName.trim().isNotEmpty) {
      final docClinicLower = matchedDoc.clinicName.trim().toLowerCase();
      final matchedClinic = _allClinics
          .where((c) => c.clinicName.trim().toLowerCase() == docClinicLower)
          .firstOrNull;
      if (matchedClinic != null && matchedClinic.id.isNotEmpty) {
        effectiveClinicId = matchedClinic.id;
      }
    }
    final normalizedMode = consultationMode.trim();
    final effectiveTreatment = (normalizedMode.isNotEmpty &&
            !treatment.toLowerCase().contains('online') &&
            !treatment.toLowerCase().contains('in-person'))
        ? '${normalizedMode.toLowerCase().contains('online') ? 'Online' : 'In-Person'} - ${treatment.trim()}'
        : treatment.trim();

    final res = await _api.createAppointment(
      patientId: pId,
      dentistId: dentistId,
      clinicId: effectiveClinicId,
      date: cleanDate,
      timeSlot: cleanSlot,
      treatment: effectiveTreatment,
      consultationMode: reqMode,
      lockId: lockId,
      releasedSlotId: releasedSlotId,
      requireLock: requireLock,
    );

    final msgLower = (res['message']?.toString() ?? '').toLowerCase();
    final reasonUpper = (res['reason']?.toString() ?? '').toUpperCase();
    final isExplicitSlotConflict = res['success'] == false &&
        (msgLower.contains('already booked') ||
         msgLower.contains('blocked') ||
         msgLower.contains('unavailable') ||
         msgLower.contains('no longer available') ||
         msgLower.contains('working day') ||
         msgLower.contains('does not consult') ||
         msgLower.contains('lunch break') ||
         msgLower.contains('break period') ||
         msgLower.contains('published slot') ||
         msgLower.contains('past dates') ||
         msgLower.contains('passed') ||
         msgLower.contains('in advance') ||
         msgLower.contains('conflicts') ||
         msgLower.contains('overlap') ||
         msgLower.contains('lock') ||
         msgLower.contains('maximum') ||
         reasonUpper == 'LOCK_REQUIRED' ||
         reasonUpper == 'LOCK_MISMATCH_OR_EXPIRED' ||
         reasonUpper == 'RELEASED_SLOT_UNAVAILABLE' ||
         reasonUpper == 'RELEASED_SLOT_LOCK_MISMATCH' ||
         reasonUpper == 'RELEASED_SLOT_LOCK_REQUIRED' ||
         reasonUpper == 'SLOT_LOCKED' ||
         reasonUpper == 'DAILY_LIMIT_REACHED' ||
         res['conflict'] == true ||
         res['isBlocked'] == true ||
         res['unavailable'] == true);

    if (isExplicitSlotConflict) {
      return res;
    }

    // Record appointment in local _requests and update availability cache immediately
    final apptMap = res['appointment'] is Map ? Map<String, dynamic>.from(res['appointment']) : <String, dynamic>{};
    final apptId = (apptMap['id'] ?? apptMap['_id'] ?? 'APT-${DateTime.now().millisecondsSinceEpoch}').toString();
    final pName = currentPatient.name.trim().isNotEmpty ? currentPatient.name.trim() : 'Patient';
    final resolvedDur = int.tryParse('${apptMap['durationMinutes'] ?? ''}') ?? BookingRulesConfig.durationForType(reqMode);
    final resolvedBuf = int.tryParse('${apptMap['bufferMinutes'] ?? ''}') ?? BookingRulesConfig.bufferForType(reqMode);
    final resolvedEnd = (apptMap['scheduledEndTime'] ?? '').toString().trim().isNotEmpty
        ? apptMap['scheduledEndTime'].toString()
        : (reqStartMin != null ? BookingRulesConfig.formatMinutesToSlot(reqStartMin + resolvedDur) : null);
    final resolvedBufEnd = (apptMap['bufferEndTime'] ?? '').toString().trim().isNotEmpty
        ? apptMap['bufferEndTime'].toString()
        : (reqStartMin != null ? BookingRulesConfig.formatMinutesToSlot(reqStartMin + resolvedDur + resolvedBuf) : null);

    final existingIdx = _requests.indexWhere((r) => r.id == apptId);
    final newReq = PatientConsultationRequest(
      id: apptId,
      patientId: pId.isNotEmpty ? pId : null,
      patientName: pName,
      patientPhone: currentPatient.phone,
      problemCategory: effectiveTreatment.isNotEmpty ? effectiveTreatment : 'Medical Consultation',
      problemDescription: symptoms.trim().isNotEmpty ? symptoms.trim() : 'Scheduled medical consultation',
      symptoms: symptoms.trim(),
      severity: 'Moderate',
      submittedAt: DateTime.now(),
      status: 'Confirmed',
      assignedDoctorId: matchedDoc.id.isNotEmpty ? matchedDoc.id : dentistId,
      assignedDoctorName: matchedDoc.name.isNotEmpty ? matchedDoc.name : null,
      assignedDoctorSpecialty: matchedDoc.specialty.isNotEmpty ? matchedDoc.specialty : 'Medical Specialist',
      assignedDoctorClinic: matchedDoc.clinicName.isNotEmpty ? matchedDoc.clinicName : (clinicId.isNotEmpty ? clinicId : null),
      assignedDoctorPhone: matchedDoc.phone,
      assignedDoctorFee: matchedDoc.consultationFee,
      confirmedDate: cleanDate,
      confirmedTimeSlot: cleanSlot,
      consultationMode: reqMode,
      durationMinutes: resolvedDur,
      bufferMinutes: resolvedBuf,
      scheduledEndTime: resolvedEnd,
      bufferEndTime: resolvedBufEnd,
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
    final idx = _requests.indexWhere((r) => r.id == appointmentId);
    if (res['success'] == true || idx != -1) {
      if (idx != -1) {
        _requests[idx].status = 'CANCELLED';
        await _saveToStorage();
      }
      if (res['success'] == true) {
        await syncAppointmentsFromApi();
      }
      notifyListeners();
      return {
        'success': true,
        'message': res['message'] ?? 'Appointment cancelled successfully.',
      };
    }
    return res;
  }

  /// Doctor/Admin: Start consultation lifecycle -> marks IN_PROGRESS & Busy – Online/In-Person Consultation
  Future<Map<String, dynamic>> startConsultation(String appointmentId) async {
    final res = await _api.startConsultation(appointmentId);
    final idx = _requests.indexWhere((r) => r.id == appointmentId);
    if (res['success'] == true || idx != -1) {
      final nowIso = DateTime.now().toIso8601String();
      if (idx != -1) {
        _requests[idx].status = 'IN_PROGRESS';
        _requests[idx].actualStartAt = nowIso;
        final mode = _requests[idx].displayConsultationMode;
        final busyStatus = mode == 'Online' ? 'Busy – Online Consultation' : 'Busy – In-Person Consultation';
        _applyLocalDoctorPresenceOverride(busyStatus, isAvailable: true);
        await _saveToStorage();
      }
      if (res['success'] == true) {
        await syncAppointmentsFromApi();
        await syncDoctorsFromApi(includeUnavailable: true);
      }
      notifyListeners();
      return res['success'] == true
          ? res
          : {'success': true, 'message': 'Consultation started locally.'};
    }
    return res;
  }

  /// Doctor/Admin: Complete consultation lifecycle -> marks COMPLETED & frees early slot if finished early
  Future<Map<String, dynamic>> completeConsultationLifecycle(String appointmentId) async {
    final res = await _api.completeConsultation(appointmentId: appointmentId);
    final idx = _requests.indexWhere((r) => r.id == appointmentId);
    if (res['success'] == true || idx != -1) {
      if (idx != -1) {
        _requests[idx].status = 'COMPLETED';
        _requests[idx].actualEndAt = DateTime.now().toIso8601String();
        _requests[idx].delayMinutes = 0;
        _applyLocalDoctorPresenceOverride('Available', isAvailable: true);
        await _saveToStorage();
      }
      if (res['success'] == true) {
        await syncAppointmentsFromApi();
        await syncDoctorsFromApi(includeUnavailable: true);
      }
      notifyListeners();
      return res['success'] == true
          ? res
          : {'success': true, 'message': 'Consultation completed locally.'};
    }
    return res;
  }

  /// Doctor/Admin: Mark consultation delayed -> notifies next patient & Admin without altering confirmed bookings
  Future<Map<String, dynamic>> markConsultationDelayed(String appointmentId, {int delayMinutes = 15}) async {
    final res = await _api.markConsultationDelayed(appointmentId, delayMinutes: delayMinutes);
    final idx = _requests.indexWhere((r) => r.id == appointmentId);
    if (res['success'] == true || idx != -1) {
      if (idx != -1) {
        _requests[idx].status = 'DELAYED';
        _requests[idx].delayMinutes = delayMinutes;
        _applyLocalDoctorPresenceOverride('Delayed', isAvailable: true);
        // Cascade local ETA update to next queued patient on same doctor & date without cancelling it
        final cur = _requests[idx];
        final curStart = BookingRulesConfig.parseClockSlotMinutes(cur.confirmedTimeSlot ?? '');
        final curDate = (cur.confirmedDate ?? '').split('T').first;
        if (curStart != null) {
          final nextList = _requests.where((r) {
            if (r.id == cur.id) return false;
            final st = r.status.toUpperCase();
            if (st == 'CANCELLED' || st == 'REJECTED' || st == 'COMPLETED' || st == 'NO_SHOW') return false;
            final rDate = (r.confirmedDate ?? '').split('T').first;
            final rStart = BookingRulesConfig.parseClockSlotMinutes(r.confirmedTimeSlot ?? '');
            return r.assignedDoctorId == cur.assignedDoctorId &&
                rDate == curDate &&
                rStart != null &&
                rStart > curStart;
          }).toList()
            ..sort((a, b) => (BookingRulesConfig.parseClockSlotMinutes(a.confirmedTimeSlot ?? '') ?? 9999)
                .compareTo(BookingRulesConfig.parseClockSlotMinutes(b.confirmedTimeSlot ?? '') ?? 9999));
          if (nextList.isNotEmpty) {
            final nextAppt = nextList.first;
            final nextStart = BookingRulesConfig.parseClockSlotMinutes(nextAppt.confirmedTimeSlot ?? '')!;
            nextAppt.delayMinutes = delayMinutes;
            nextAppt.estimatedStartTime = BookingRulesConfig.minutesToClockSlot(nextStart + delayMinutes);
          }
        }
        await _saveToStorage();
      }
      if (res['success'] == true) {
        await syncAppointmentsFromApi();
        await syncDoctorsFromApi(includeUnavailable: true);
      }
      notifyListeners();
      return res['success'] == true
          ? res
          : {'success': true, 'message': 'Consultation marked delayed ($delayMinutes mins).'};
    }
    return res;
  }

  /// Doctor/Admin: Mark patient no-show and release slot
  Future<Map<String, dynamic>> markPatientNoShow(String appointmentId) async {
    final res = await _api.markPatientNoShow(appointmentId);
    final idx = _requests.indexWhere((r) => r.id == appointmentId);
    if (res['success'] == true || idx != -1) {
      if (idx != -1) {
        _requests[idx].status = 'NO_SHOW';
        _requests[idx].delayMinutes = 0;
        _applyLocalDoctorPresenceOverride('Available', isAvailable: true);
        await _saveToStorage();
      }
      if (res['success'] == true) {
        await syncAppointmentsFromApi();
        await syncDoctorsFromApi(includeUnavailable: true);
      }
      notifyListeners();
      return res['success'] == true
          ? res
          : {'success': true, 'message': 'Marked Patient No-Show.'};
    }
    return res;
  }

  /// Patient: Submit response to doctor running late (WAIT, REQUEST_RESCHEDULE, SWITCH_DOCTOR)
  Future<Map<String, dynamic>> submitPatientDelayResponse({
    required String appointmentId,
    required String action,
    String? requestedDate,
    String? requestedTimeSlot,
    String? reason,
  }) async {
    final res = await _api.submitPatientDelayResponse(
      appointmentId: appointmentId,
      action: action,
      requestedDate: requestedDate,
      requestedTimeSlot: requestedTimeSlot,
      reason: reason,
    );
    final idx = _requests.indexWhere((r) => r.id == appointmentId);
    if (idx != -1 && (res['success'] == true || action.isNotEmpty)) {
      _requests[idx].patientDelayChoice = action.toUpperCase();
      if (action.toUpperCase() == 'REQUEST_RESCHEDULE') {
        _requests[idx].rescheduleRequestStatus = 'PENDING';
        _requests[idx].rescheduleRequestedDate = requestedDate;
        _requests[idx].rescheduleRequestedSlot = requestedTimeSlot;
        _requests[idx].rescheduleRequestReason = reason ?? 'Requested reschedule';
      }
      await _saveToStorage();
      notifyListeners();
    }
    if (res['success'] == true) {
      return res;
    }
    return {
      'success': true,
      'action': action.toUpperCase(),
      'alternateDoctors': action.toUpperCase() == 'SWITCH_DOCTOR'
          ? _allDoctors.where((d) => d.isAvailable).map((d) => {'id': d.id, 'name': d.name, 'specialty': d.specialty}).toList()
          : const [],
      'message': 'Response saved locally.',
    };
  }

  void _applyLocalDoctorPresenceOverride(String statusText, {required bool isAvailable}) {
    if (currentDoctor != null) {
      currentDoctor = currentDoctor!.copyWith(status: statusText, onlineStatus: statusText);
      final idx = _allDoctors.indexWhere((d) => d.id == currentDoctor!.id);
      if (idx != -1) {
        _allDoctors[idx] = _allDoctors[idx].copyWith(status: statusText, onlineStatus: statusText);
      }
    }
  }

  Future<Map<String, dynamic>> getSchedulingRules() => _api.fetchSchedulingRules();

  Future<Map<String, dynamic>> updateSchedulingRules(Map<String, dynamic> rules) async {
    final res = await _api.updateSchedulingRules(rules);
    notifyListeners();
    return res;
  }

  Future<Map<String, dynamic>> getLiveSchedulingStatus({String? date}) =>
      _api.fetchLiveSchedulingStatus(date: date);

  Future<Map<String, dynamic>> blockDoctorTimeSlot({
    required String doctorId,
    required DateTime date,
    required String startTime,
    String? endTime,
    String reason = 'Blocked by Admin',
  }) async {
    final dateStr = _formatYmdLocal(date);
    final res = await _api.blockDoctorTimeSlot(
      dentistId: doctorId,
      date: dateStr,
      startTime: startTime,
      endTime: endTime,
      reason: reason,
    );
    _availabilityCache.remove('${doctorId}_$dateStr');
    notifyListeners();
    return res;
  }

  Future<Map<String, dynamic>> unblockDoctorTimeSlot({
    required String doctorId,
    required DateTime date,
    required String startTime,
  }) async {
    final dateStr = _formatYmdLocal(date);
    final res = await _api.unblockDoctorTimeSlot(
      dentistId: doctorId,
      date: dateStr,
      startTime: startTime,
    );
    _availabilityCache.remove('${doctorId}_$dateStr');
    notifyListeners();
    return res;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dentaguru_patient_profile', jsonEncode(currentPatient.toJson()));
      if (currentPatient.id.trim().isNotEmpty) {
        await prefs.setString('dentaguru_patient_profile_${currentPatient.id.trim()}', jsonEncode(currentPatient.toJson()));
      }
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
      await prefs.setString('dentaguru_app_notifications', jsonEncode(_appNotifications.map((n) => n.toJson()).toList()));
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
          'assignedDistricts': _subAdminDistricts,
        }));
      } else {
        await prefs.remove('dentaguru_sub_admin_session');
      }

      await prefs.setString('dentaguru_districts_cache', jsonEncode(_districts));

      if (_isClinicMode) {
        await prefs.setString('dentaguru_clinic_session', jsonEncode({
          'isClinicMode': _isClinicMode,
          'id': _authenticatedClinicId,
          'clinicName': _authenticatedClinicName,
          'location': _authenticatedClinicLocation,
          'phone': _authenticatedClinicPhone,
          'email': _authenticatedClinicEmail,
          'isFeatured': _authenticatedClinicIsFeatured,
          'featuredPlan': _authenticatedClinicFeaturedPlan,
          'coverImageUrl': _authenticatedClinicCoverUrl,
        }));
      } else {
        await prefs.remove('dentaguru_clinic_session');
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
      _isDentistMode = false;
      _allDoctors.clear();
      _allPatients.clear();
      _allClinics.clear();
      _requests.clear();
      _dentistAssignedRequests.clear();
      _myCreatedPatientReferrals.clear();
      _doctorReceivedPatientReferrals.clear();
      _receivedForMePatientReferrals.clear();
      _clinicPatientReferrals.clear();
      _adminPatientReferrals.clear();
      _medicalRecords.clear();
      _doctorSharedRecords.clear();
      _appNotifications.clear();
      _isClinicMode = false;
      _authenticatedClinicId = '';
      _authenticatedClinicName = '';
      _authenticatedClinicLocation = '';
      _authenticatedClinicPhone = '';
      _authenticatedClinicEmail = '';
      _authenticatedClinicIsFeatured = false;
      _authenticatedClinicFeaturedPlan = '';
      _authenticatedClinicCoverUrl = '';
      _authenticatedClinicCoverBytes = null;
      _clinicCoverBytesByKey.clear();
      _clinicCoverUrlByKey.clear();
      _clinicFeaturedByKey.clear();
      _clinicFeaturedPlanByKey.clear();
      _availabilityCache.clear();
      _doctorScheduleCache.clear();
      _blockedDatesCache.clear();
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
    String state = '',
    List<String>? languages,
    Uint8List? photoBytes,
    String? profileImageUrl,
    bool preserveExistingPhoto = true,
    bool syncRemote = true,
  }) {
    final cleanEmailKey = email.trim().toLowerCase();
    if (photoBytes != null && cleanEmailKey.isNotEmpty) {
      _userPhotoCache[cleanEmailKey] = photoBytes;
    }
    final cachedPhoto = photoBytes ??
        (preserveExistingPhoto
            ? ((cleanEmailKey.isNotEmpty ? _userPhotoCache[cleanEmailKey] : null) ??
                currentPatient.photoBytes)
            : null);
    final effectiveImageUrl = (profileImageUrl != null && profileImageUrl.trim().isNotEmpty)
        ? profileImageUrl.trim()
        : (preserveExistingPhoto && photoBytes == null ? currentPatient.profileImageUrl : null);

    final effectiveLanguages = (languages != null && languages.isNotEmpty)
        ? List<String>.from(languages)
        : (currentPatient.languages.isNotEmpty ? List<String>.from(currentPatient.languages) : <String>['English']);
    final effectiveId = id.trim().isNotEmpty ? id.trim() : currentPatient.id;
    final effectiveState = state.trim().isNotEmpty ? state.trim() : currentPatient.state;
    final cleanGender = gender.trim().toLowerCase() == 'null' ? '' : gender.trim();
    final cleanAge = age.trim().toLowerCase() == 'null' ? '' : age.trim();
    final cleanPincode = pincode.trim().toLowerCase() == 'null' ? '' : pincode.trim();

    currentPatient = PatientProfile(
      id: effectiveId,
      name: name.trim().isEmpty ? 'Patient' : name.trim(),
      email: email.trim().isEmpty ? 'patient@dentaguru.com' : email.trim(),
      phone: phone.trim(),
      age: cleanAge,
      gender: cleanGender,
      bloodGroup: bloodGroup.trim().isEmpty ? 'O Positive (O+)' : bloodGroup.trim(),
      emergencyContact: emergencyContact.trim().isEmpty ? phone.trim() : emergencyContact.trim(),
      address: address.trim(),
      city: city.trim(),
      pincode: cleanPincode,
      state: effectiveState,
      languages: effectiveLanguages,
      photoBytes: cachedPhoto,
      profileImageUrl: effectiveImageUrl,
    );
    _saveToStorage();

    if (syncRemote && (email.trim().isNotEmpty || phone.trim().isNotEmpty || effectiveId.isNotEmpty)) {
      try {
        final photoPayload = cachedPhoto != null
            ? 'data:image/png;base64,${base64Encode(cachedPhoto)}'
            : effectiveImageUrl;
        ApiService().updatePatientProfileApi(
          patientId: effectiveId,
          name: currentPatient.name,
          age: cleanAge,
          gender: cleanGender,
          pincode: cleanPincode,
          city: city.trim(),
          address: address.trim(),
          bloodGroup: currentPatient.bloodGroup,
          emergencyContact: currentPatient.emergencyContact,
          languages: effectiveLanguages,
          profilePhoto: photoPayload,
          completeProfile: false,
        );
      } catch (_) {}
      syncAllDataFromApi();
    }

    notifyListeners();
  }

  /// Persists deferred Patient Profile Completion against the existing authenticated Patient ID
  /// without creating duplicate accounts.
  Future<Map<String, dynamic>> completePatientProfile({
    required Uint8List? photoBytes,
    String? profileImageUrl,
    required String pincode,
    required String age,
    required String gender,
    String? name,
    String? city,
    String? address,
    String? bloodGroup,
    List<String>? languages,
  }) async {
    final cleanPin = pincode.trim();
    final cleanAge = age.trim();
    final cleanGender = gender.trim();
    final cleanNameInput = (name ?? '').trim();
    final cleanAddressInput =
        address != null ? address.trim() : currentPatient.address.trim();
    final cleanBloodInput =
        bloodGroup != null ? bloodGroup.trim() : currentPatient.bloodGroup.trim();
    final effectiveLanguages = (languages != null && languages.isNotEmpty)
        ? languages.map((l) => l.trim()).where((l) => l.isNotEmpty).toList()
        : (currentPatient.languages.isNotEmpty
            ? currentPatient.languages
            : <String>['English']);
    final effectiveBytes = photoBytes ?? currentPatient.photoBytes;
    final effectiveUrl = (profileImageUrl != null && profileImageUrl.trim().isNotEmpty)
        ? profileImageUrl.trim()
        : currentPatient.profileImageUrl;
    final bool hasImage = (effectiveBytes != null && effectiveBytes.isNotEmpty) ||
        (effectiveUrl != null && effectiveUrl.isNotEmpty);

    if (PatientProfileRequirementsConfig.requireProfileImage && !hasImage) {
      return {'success': false, 'message': 'Please upload a profile image.'};
    }
    if (PatientProfileRequirementsConfig.requireFullName &&
        cleanNameInput.isEmpty &&
        !currentPatient.hasValidFullName) {
      return {'success': false, 'message': 'Please enter your full name.'};
    }
    if (PatientProfileRequirementsConfig.requireAddress &&
        cleanAddressInput.isEmpty) {
      return {'success': false, 'message': 'Please enter your address.'};
    }
    if (PatientProfileRequirementsConfig.requirePincode || cleanPin.isNotEmpty) {
      if (!RegExp(r'^\d{6}$').hasMatch(cleanPin)) {
        return {'success': false, 'message': 'Please enter a valid 6-digit pincode.'};
      }
    }
    if (PatientProfileRequirementsConfig.requireAge || cleanAge.isNotEmpty) {
      final parsedAge = int.tryParse(cleanAge);
      if (!RegExp(r'^\d+$').hasMatch(cleanAge) ||
          parsedAge == null ||
          parsedAge < 1 ||
          parsedAge > 120) {
        return {'success': false, 'message': 'Please enter a valid age between 1 and 120.'};
      }
    }
    if (PatientProfileRequirementsConfig.requireGender &&
        (cleanGender.isEmpty || cleanGender.toLowerCase() == 'null')) {
      return {'success': false, 'message': 'Please select your gender.'};
    }
    if (PatientProfileRequirementsConfig.requirePreferredLanguage &&
        effectiveLanguages.isEmpty) {
      return {'success': false, 'message': 'Please select at least one preferred language.'};
    }
    if (PatientProfileRequirementsConfig.requireBloodGroup &&
        cleanBloodInput.isEmpty) {
      return {'success': false, 'message': 'Please select your blood group.'};
    }

    final sess = SessionService().currentSession;
    final existingPatientId = currentPatient.id.trim().isNotEmpty
        ? currentPatient.id.trim()
        : (sess?.userId.trim() ?? '');
    if (existingPatientId.isEmpty) {
      return {'success': false, 'message': 'No active patient session found. Please sign in again.'};
    }

    final String photoData = effectiveBytes != null && effectiveBytes.isNotEmpty
        ? 'data:image/png;base64,${base64Encode(effectiveBytes)}'
        : (effectiveUrl ?? '');
    final effectiveName = cleanNameInput.isNotEmpty
        ? cleanNameInput
        : (currentPatient.name.trim().isNotEmpty ? currentPatient.name.trim() : (sess?.name ?? 'Patient'));
    final effectiveCity = (city != null && city.trim().isNotEmpty)
        ? city.trim()
        : currentPatient.city;

    final apiRes = await _api.updatePatientProfileApi(
      patientId: existingPatientId,
      pincode: cleanPin,
      age: cleanAge,
      gender: cleanGender,
      profilePhoto: photoData.isNotEmpty ? photoData : null,
      name: effectiveName,
      city: effectiveCity,
      address: cleanAddressInput,
      bloodGroup: cleanBloodInput,
      languages: effectiveLanguages,
      completeProfile: true,
    );

    if (apiRes['success'] != true) {
      return {
        'success': false,
        'message': apiRes['message']?.toString() ?? 'Failed to save profile details.',
      };
    }

    updatePatientProfile(
      id: existingPatientId,
      name: effectiveName,
      email: currentPatient.email.isNotEmpty ? currentPatient.email : (sess?.email ?? ''),
      phone: currentPatient.phone.isNotEmpty ? currentPatient.phone : (sess?.phone ?? ''),
      age: cleanAge,
      gender: cleanGender,
      bloodGroup: cleanBloodInput,
      emergencyContact: currentPatient.emergencyContact,
      address: cleanAddressInput,
      city: effectiveCity,
      pincode: cleanPin,
      state: currentPatient.state,
      languages: effectiveLanguages,
      photoBytes: effectiveBytes,
      profileImageUrl: effectiveBytes == null ? effectiveUrl : null,
      preserveExistingPhoto: true,
      syncRemote: false,
    );

    await SessionService().updateSessionUser(
      name: effectiveName,
      additionalMetadata: {
        'age': cleanAge,
        'gender': cleanGender,
        'pincode': cleanPin,
        'city': effectiveCity,
        'address': cleanAddressInput,
        'bloodGroup': cleanBloodInput,
        'languages': effectiveLanguages,
        if (photoData.isNotEmpty) 'profilePhoto': photoData,
        'isProfileComplete': true,
      },
    );

    return {'success': true, 'message': 'Profile completed successfully.'};
  }

  /// Clears only cached active patient profile fields on logout or user switch.
  Future<void> clearPatientSessionCache() async {
    currentPatient = PatientProfile();
    _userPhotoCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dentaguru_patient_profile');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> updatePatientLanguages(List<String> languages) async {
    final cleaned = languages
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList();
    final effectiveLanguages = cleaned.isNotEmpty ? cleaned : <String>['English'];

    currentPatient.languages = effectiveLanguages;
    await _saveToStorage();
    notifyListeners();

    try {
      final profileMeta = jsonEncode({
        'age': currentPatient.age.trim(),
        'bloodGroup': currentPatient.bloodGroup.trim(),
        'gender': currentPatient.gender.trim(),
        'emergencyContact': currentPatient.emergencyContact.trim(),
        'city': currentPatient.city.trim(),
        'pincode': currentPatient.pincode.trim(),
        'state': currentPatient.state.trim(),
        'address': currentPatient.address.trim(),
        'languages': effectiveLanguages,
      });
      if (currentPatient.id.trim().isNotEmpty) {
        await Supabase.instance.client
            .from('users')
            .update({'device_token': profileMeta})
            .eq('id', currentPatient.id.trim());
      } else if (currentPatient.email.trim().isNotEmpty) {
        await Supabase.instance.client
            .from('users')
            .update({'device_token': profileMeta})
            .ilike('email', currentPatient.email.trim());
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> deleteCurrentPatientAccount() async {
    final pId = currentPatient.id.trim();
    final pEmail = currentPatient.email.trim();
    final pPhone = currentPatient.phone.trim();

    try {
      if (pId.isNotEmpty) {
        await Supabase.instance.client.from('users').delete().eq('id', pId);
      } else if (pEmail.isNotEmpty) {
        await Supabase.instance.client.from('users').delete().ilike('email', pEmail);
      } else if (pPhone.isNotEmpty) {
        await Supabase.instance.client.from('users').delete().eq('phone', pPhone);
      }
    } catch (_) {}

    await clearAllData();
    return {
      'success': true,
      'message': 'Patient account deleted successfully.',
    };
  }

  /// Permanently delete currently logged-in Doctor account across Supabase & Express
  Future<Map<String, dynamic>> deleteCurrentDoctorAccount() async {
    final doc = currentDoctor;
    final dId = doc?.id.trim() ?? '';
    final uId = doc?.userId.trim() ?? '';
    final dEmail = doc?.email.trim() ?? '';
    final dPhone = doc?.phone.trim() ?? '';

    if (dId.isNotEmpty) {
      await ApiService().deleteDoctor(dId);
    } else if (uId.isNotEmpty) {
      await ApiService().deleteDoctor(uId);
    }

    try {
      if (dEmail.isNotEmpty) {
        await Supabase.instance.client.from('dentists').delete().ilike('email', dEmail);
        await Supabase.instance.client.from('users').delete().ilike('email', dEmail);
      } else if (dPhone.isNotEmpty) {
        await Supabase.instance.client.from('dentists').delete().eq('phone', dPhone);
        await Supabase.instance.client.from('users').delete().eq('phone', dPhone);
      }
    } catch (_) {}

    await clearAllDataAndStorage();
    return {
      'success': true,
      'message': 'Doctor account deleted successfully.',
    };
  }

  /// Permanently delete currently logged-in Clinic account across Supabase & Express
  Future<Map<String, dynamic>> deleteCurrentClinicAccount({
    String? clinicId,
    String? clinicName,
  }) async {
    final cId = (clinicId ?? _authenticatedClinicId).trim();
    final cName = (clinicName ?? _authenticatedClinicName).trim();
    final cPhone = _authenticatedClinicPhone.trim();
    final cEmail = _authenticatedClinicEmail.trim();

    final supaUser = SupabaseService.safeCurrentUser;
    final uId = supaUser?.id ?? SessionService().currentSession?.userId ?? '';

    // 1. Direct Supabase Cloud Deletion
    try {
      final client = Supabase.instance.client;
      if (cId.isNotEmpty) {
        await client.from('clinics').delete().eq('id', cId);
      }
      if (uId.isNotEmpty) {
        await client.from('clinics').delete().eq('user_id', uId);
        await client.from('users').delete().eq('id', uId);
      }
      if (cEmail.isNotEmpty) {
        await client.from('users').delete().ilike('email', cEmail);
      } else if (cPhone.isNotEmpty) {
        await client.from('users').delete().eq('phone', cPhone);
      }
    } catch (e) {
      debugPrint('Supabase direct delete clinic account notice: $e');
    }

    // 2. Express Backend API Call
    try {
      if (cId.isNotEmpty) {
        await ApiService().deleteClinic(cId);
      }
    } catch (e) {
      debugPrint('Express delete clinic error: $e');
    }

    // 3. Clear local state
    if (cId.isNotEmpty) {
      _allClinics.removeWhere((c) => c.id == cId);
    }
    if (cName.isNotEmpty) {
      _allClinics.removeWhere((c) => c.clinicName.toLowerCase() == cName.toLowerCase());
    }
    await clearClinicSession();
    await _saveToStorage();
    notifyListeners();

    return {
      'success': true,
      'message': 'Clinic account deleted successfully.',
    };
  }

  Future<void> submitProblem({
    required String problemCategory,
    required String problemDescription,
    required String severity,
    String? specialty,
    String symptoms = '',
    String preferredLocation = '',
    List<String> attachments = const [],
    String? preferredDoctorId,
    String? preferredDoctorName,
    String? preferredDoctorClinic,
    String? referringDentistId,
    String? referringDentistName,
    String? escalationType,
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
    final bool isCoordinatorEscalation =
        !isDirectReferral && escalationType?.toUpperCase() == 'COORDINATOR_ASSISTANCE';

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
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : _safeAuthUserId;
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
      status: isDirectReferral
          ? 'DENTIST_ASSIGNED'
          : (isCoordinatorEscalation ? 'Submitted' : 'PENDING_ADMIN_REVIEW'),
      city: pCity,
      pincode: pPincode,
      state: pState,
      preferredDoctorId: preferredDoctorId,
      preferredDoctorName: preferredDoctorName ?? doc?.name,
      preferredDoctorClinic: preferredDoctorClinic ?? doc?.clinicName,
      assignedDoctorId: isDirectReferral ? (doc?.id ?? preferredDoctorId) : null,
      assignedDoctorName: isDirectReferral ? (doc?.name ?? preferredDoctorName) : null,
      assignedDoctorSpecialty: isDirectReferral
          ? (doc?.specialty.isNotEmpty == true ? doc!.specialty : (specialty ?? problemCategory))
          : (specialty != null && specialty.trim().isNotEmpty ? specialty.trim() : null),
      assignedDoctorClinic: isDirectReferral ? (doc?.clinicName ?? preferredDoctorClinic) : null,
      assignedDoctorPhone: isDirectReferral ? (doc?.phone ?? '') : null,
      assignedDoctorFee: isDirectReferral ? (doc?.consultationFee ?? '') : null,
      adminNotes: isDirectReferral
          ? 'Referral directly assigned to ${doc?.name ?? preferredDoctorName}'
          : (isCoordinatorEscalation
              ? 'Coordinator assistance requested${specialty != null && specialty.isNotEmpty ? ' for $specialty' : ''}.'
              : null),
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
        specialty: specialty,
        city: pCity,
        pincode: pPincode,
        state: pState,
        preferredDoctorId: preferredDoctorId,
        preferredDoctorName: preferredDoctorName,
        preferredDoctorClinic: preferredDoctorClinic,
        referringDentistId: referringDentistId,
        referringDentistName: referringDentistName,
        escalationType: escalationType,
      );
      // Replace temp record with the server-assigned UUID record
      await syncProblemRequestsFromApi();
    } catch (e) {
      debugPrint('Error saving problem request to Supabase DB: $e');
    }
  }

  /// Coordinator Escalation 6-stage lifecycle helpers & update method
  static const List<String> coordinatorLifecycleStages = <String>[
    'Submitted',
    'Assigned',
    'Contacting Patient',
    'Doctor Identified',
    'Resolved',
    'Closed',
  ];

  Future<Map<String, dynamic>> updateCoordinatorRequestStatus({
    required String requestId,
    required String status,
    String? followUpNote,
    String? coordinatorId,
    String? coordinatorName,
    String? doctorId,
  }) async {
    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx != -1) {
      _requests[idx].status = status;
      if (followUpNote != null && followUpNote.trim().isNotEmpty) {
        _requests[idx].adminNotes = followUpNote.trim();
      }
      _saveToStorage();
      notifyListeners();
    }
    final res = await _api.updateCoordinatorStatus(
      requestId: requestId,
      status: status,
      followUpNote: followUpNote,
      coordinatorId: coordinatorId,
      coordinatorName: coordinatorName,
      doctorId: doctorId,
    );
    if (res['success'] == true) {
      await syncProblemRequestsFromApi();
    }
    return res;
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
    final category = reqObj?.problemCategory ?? 'Medical Consultation';

    addNotification(
      recipientRole: 'Patient',
      recipientId: reqName,
      title: '🎉 Consultation Accepted!',
      message: '$docName accepted your consultation for $category. Confirmed Time Slot: $slotText',
    );

    addNotification(
      recipientRole: 'Admin',
      recipientId: 'ALL_ADMINS',
      title: '✅ Doctor Accepted Referral',
      message: '$docName accepted consultation for $reqName. Time Slot: $slotText',
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
    bool acceptedAppointment = false;
    try {
      final apptRes = await ApiService().acceptAppointment(requestId);
      if (apptRes['success'] == true) {
        acceptedAppointment = true;
      }
    } catch (_) {}

    if (!acceptedAppointment) {
      try {
        await ApiService().acceptProblemRequest(
          requestId: requestId,
          timeSlot: slotText,
          date: date,
        );
      } catch (e) {
        debugPrint('Backend API acceptProblemRequest notice: $e');
      }
    }

    // 3. Only create a new appointment if this was a triage problem request (not an existing appointment record)
    if (!acceptedAppointment && reqObj != null && requestId.startsWith('PR-')) {
      ApiService().createAppointment(
        patientId: reqObj.patientId ?? reqObj.patientName,
        dentistId: reqObj.assignedDoctorId ?? '',
        clinicId: reqObj.assignedDoctorClinic ?? '',
        date: date ?? DateTime.now().toIso8601String(),
        timeSlot: slotText,
        treatment: reqObj.problemCategory,
      ).then((_) => syncAppointmentsFromApi()).catchError((e) {
        debugPrint('Error persisting appointment in acceptReferralByDentist: $e');
      });
    } else {
      syncAppointmentsFromApi();
      syncNotificationsFromApi(role: 'Dentist');
    }
  }

  /// Doctor: Accept / Confirm a Pending Appointment directly from the Doctor Dashboard
  Future<Map<String, dynamic>> acceptAppointmentByDoctor(String appointmentId) async {
    final index = _requests.indexWhere((r) => r.id == appointmentId);
    final assignedIndex = _dentistAssignedRequests.indexWhere((r) => r.id == appointmentId);

    String patientName = 'Patient';
    String patientId = '';
    String? slot;
    String? dateStr;

    if (index != -1) {
      _requests[index].status = 'CONFIRMED';
      patientName = _requests[index].patientName;
      patientId = _requests[index].patientId ?? '';
      slot = _requests[index].confirmedTimeSlot;
      dateStr = _requests[index].confirmedDate;
    }
    if (assignedIndex != -1) {
      _dentistAssignedRequests[assignedIndex].status = 'CONFIRMED';
      patientName = _dentistAssignedRequests[assignedIndex].patientName;
      patientId = _dentistAssignedRequests[assignedIndex].patientId ?? patientId;
      slot ??= _dentistAssignedRequests[assignedIndex].confirmedTimeSlot;
      dateStr ??= _dentistAssignedRequests[assignedIndex].confirmedDate;
    }

    await _saveToStorage();
    notifyListeners();

    Map<String, dynamic> res = {'success': false};
    try {
      res = await _api.acceptAppointment(appointmentId);
      if (res['success'] != true) {
        final prRes = await _api.acceptProblemRequest(
          requestId: appointmentId,
          timeSlot: slot,
          date: dateStr,
        );
        if (prRes['success'] == true) {
          res = {'success': true, 'message': 'Appointment confirmed successfully.'};
        }
      }
    } catch (e) {
      debugPrint('acceptAppointmentByDoctor API notice: $e');
    }

    addNotification(
      recipientRole: 'Patient',
      recipientId: patientId.isNotEmpty ? patientId : patientName,
      title: '🎉 Appointment Confirmed',
      message: 'Your appointment with ${currentDoctor?.name ?? "your doctor"} has been confirmed.',
    );

    await syncAppointmentsFromApi();
    await syncNotificationsFromApi(role: 'Dentist');
    await _saveToStorage();
    notifyListeners();

    return {
      'success': true,
      'message': res['message']?.toString() ?? 'Appointment confirmed for $patientName!',
    };
  }

  /// Doctor: Decline / Reject a Pending Appointment from the Doctor Dashboard
  Future<Map<String, dynamic>> rejectAppointmentByDoctor(
    String appointmentId, {
    String? reason,
  }) async {
    final index = _requests.indexWhere((r) => r.id == appointmentId);
    final assignedIndex = _dentistAssignedRequests.indexWhere((r) => r.id == appointmentId);

    String patientName = 'Patient';
    String patientId = '';

    if (index != -1) {
      _requests[index].status = 'REJECTED';
      patientName = _requests[index].patientName;
      patientId = _requests[index].patientId ?? '';
    }
    if (assignedIndex != -1) {
      _dentistAssignedRequests[assignedIndex].status = 'REJECTED';
      patientName = _dentistAssignedRequests[assignedIndex].patientName;
      patientId = _dentistAssignedRequests[assignedIndex].patientId ?? patientId;
    }

    await _saveToStorage();
    notifyListeners();

    Map<String, dynamic> res = {'success': false};
    try {
      res = await _api.rejectAppointment(appointmentId, reason: reason);
    } catch (e) {
      debugPrint('rejectAppointmentByDoctor API notice: $e');
    }

    addNotification(
      recipientRole: 'Patient',
      recipientId: patientId.isNotEmpty ? patientId : patientName,
      title: '❌ Appointment Declined',
      message: reason != null && reason.trim().isNotEmpty
          ? 'Your appointment request was declined: $reason'
          : 'Your appointment request was declined by the doctor.',
    );

    await syncAppointmentsFromApi();
    await syncNotificationsFromApi(role: 'Dentist');
    await _saveToStorage();
    notifyListeners();

    return {
      'success': true,
      'message': res['message']?.toString() ?? 'Appointment declined for $patientName.',
    };
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
    String userId = '',
    String clinicId = '',
    required String name,
    required String email,
    required String phone,
    required String licenseNumber,
    required String specialty,
    required String clinicName,
    required int experienceYears,
    String password = 'Password123!',
    String qualification = '',
    String consultationFee = '',
    String bio = '',
    String status = 'Available',
    Uint8List? photoBytes,
    String? profileImageUrl,
    String clinicAddress = '',
    String state = '',
    String city = '',
    String pincode = '',
    double? latitude,
    double? longitude,
    List<String>? languages,
    bool skipApiRegister = false,
    bool setAsCurrentDoctor = true,
  }) {
    final cleanEmail = email.trim();
    if (photoBytes != null && cleanEmail.isNotEmpty) {
      _userPhotoCache[cleanEmail.toLowerCase()] = photoBytes;
    }
    final cachedPhoto = photoBytes ?? (cleanEmail.isNotEmpty ? _userPhotoCache[cleanEmail.toLowerCase()] : null);

    final formattedName = name.trim().startsWith('Dr.') ? name.trim() : 'Dr. ${name.trim()}';
    final rawLic = licenseNumber.trim();
    final cleanLicense = (rawLic.isEmpty ||
            rawLic.toLowerCase() == 'med-lic-reg' ||
            rawLic.toLowerCase() == 'med-lic-registered')
        ? ''
        : rawLic;
    final cleanClinic = clinicName.trim();
    final cleanSpecialty = specialty.trim().isEmpty ? 'General Medicine' : specialty.trim();
    final cleanQual = qualification.trim().isEmpty
        ? MedicalSpecialtyModel.getDefaultQualificationForSpecialty(cleanSpecialty)
        : qualification.trim();
    final cleanAddress = clinicAddress.trim();
    final cleanCity = city.trim();
    final cleanPincode = pincode.trim();
    final cleanPhone = phone.trim();
    final phoneDigits = cleanPhone.replaceAll(RegExp(r'\D'), '');
    final phoneLast10 = phoneDigits.length >= 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;
    final doctorLangs = (languages != null && languages.isNotEmpty) ? languages : const ['English'];

    final existingDoc = _allDoctors.firstWhere(
      (d) {
        if (id.trim().isNotEmpty && (d.id == id.trim() || d.userId == id.trim())) return true;
        if (userId.trim().isNotEmpty && (d.userId == userId.trim() || d.id == userId.trim())) return true;
        if (cleanEmail.isNotEmpty && d.email.trim().toLowerCase() == cleanEmail.toLowerCase()) return true;
        if (phoneLast10.length >= 10) {
          final dDigits = d.phone.replaceAll(RegExp(r'\D'), '');
          final dLast10 = dDigits.length >= 10 ? dDigits.substring(dDigits.length - 10) : dDigits;
          if (dLast10 == phoneLast10) return true;
        }
        return false;
      },
      orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''),
    );
    final doctorId = existingDoc.id.isNotEmpty
        ? existingDoc.id
        : (id.trim().isNotEmpty
            ? id.trim()
            : 'DOC-${DateTime.now().microsecondsSinceEpoch}-${_allDoctors.length + 1}');
    final doctorUserId = userId.trim().isNotEmpty
        ? userId.trim()
        : (existingDoc.userId.isNotEmpty ? existingDoc.userId : id.trim());
    final resolvedClinicId = clinicId.trim().isNotEmpty
        ? clinicId.trim()
        : (_allClinics
                .where((c) => cleanClinic.isNotEmpty && c.clinicName.trim().toLowerCase() == cleanClinic.toLowerCase())
                .map((c) => c.id)
                .firstOrNull ??
            '');

    final newDoctor = DoctorModel(
      id: doctorId,
      userId: doctorUserId,
      clinicId: resolvedClinicId,
      name: formattedName.isEmpty ? (cleanEmail.isNotEmpty ? cleanEmail : 'Doctor') : formattedName,
      specialty: cleanSpecialty,
      qualification: cleanQual,
      experienceYears: experienceYears <= 0 ? 5 : experienceYears,
      rating: 5.0,
      reviewCount: 1,
      clinicName: cleanClinic,
      phone: cleanPhone,
      email: cleanEmail,
      status: status.trim().isNotEmpty ? status.trim() : (existingDoc.status.isNotEmpty ? existingDoc.status : 'Available'),
      nextAvailableSlots: existingDoc.nextAvailableSlots,
      consultationFee: consultationFee.trim(),
      licenseNumber: cleanLicense,
      photoBytes: cachedPhoto,
      profileImageUrl: (profileImageUrl != null && profileImageUrl.trim().isNotEmpty)
          ? profileImageUrl.trim()
          : existingDoc.profileImageUrl,
      clinicAddress: cleanAddress,
      city: cleanCity,
      state: state.trim(),
      pincode: cleanPincode,
      bio: bio.trim(),
      latitude: latitude,
      longitude: longitude,
      languages: doctorLangs,
    );

    final matchIdx = _allDoctors.indexWhere((d) =>
        (newDoctor.id.isNotEmpty && d.id == newDoctor.id) ||
        (newDoctor.email.isNotEmpty && d.email.toLowerCase() == newDoctor.email.toLowerCase()) ||
        (phoneLast10.length >= 10 &&
            d.phone.replaceAll(RegExp(r'\D'), '').endsWith(phoneLast10)));
    if (matchIdx == -1) {
      _allDoctors.insert(0, newDoctor);
    } else {
      _allDoctors[matchIdx] = newDoctor;
    }

    if (setAsCurrentDoctor) {
      if (currentDoctor?.id != newDoctor.id ||
          (newDoctor.email.isNotEmpty && currentDoctor?.email.toLowerCase() != newDoctor.email.toLowerCase())) {
        _dentistAssignedRequests.clear();
        _doctorReceivedPatientReferrals.clear();
        _doctorSharedRecords.clear();
        _adminPatientReferrals.clear();
      }
      currentDoctor = newDoctor;
    }

    if (cleanClinic.isNotEmpty && !_allClinics.any((c) => c.clinicName.trim().toLowerCase() == cleanClinic.toLowerCase())) {
      _allClinics.insert(
        0,
        ClinicModel(
          id: resolvedClinicId.isNotEmpty ? resolvedClinicId : 'CLN-${DateTime.now().millisecondsSinceEpoch}',
          clinicName: cleanClinic,
          location: cleanAddress.isNotEmpty ? (cleanCity.isNotEmpty ? '$cleanAddress, $cleanCity' : cleanAddress) : cleanCity,
          verified: true,
          services: [cleanSpecialty, 'General Consultation'],
        ),
      );
    }

    _saveToStorage();
    notifyListeners();

    // End-to-end Real-Time Persistence into Supabase ('users', 'clinics', 'dentists')
    if (!skipApiRegister) {
      ApiService().registerUser(
        name: formattedName,
        email: cleanEmail.isEmpty ? null : cleanEmail,
        password: password.trim().isEmpty ? 'Password123!' : password.trim(),
        phone: cleanPhone.isEmpty ? '+91${DateTime.now().millisecondsSinceEpoch.toString().substring(3)}' : cleanPhone,
        role: 'Dentist',
        specialty: cleanSpecialty,
        licenseNumber: cleanLicense.isEmpty ? null : cleanLicense,
        clinicId: resolvedClinicId.isNotEmpty ? resolvedClinicId : null,
        clinicName: cleanClinic,
        clinicAddress: cleanAddress,
        state: state.trim().isEmpty ? null : state.trim(),
        latitude: latitude,
        longitude: longitude,
        consultationFee: consultationFee.trim().isEmpty ? null : consultationFee.trim(),
        bio: bio.trim().isEmpty ? null : bio.trim(),
        location: cleanAddress,
        city: cleanCity,
        pincode: cleanPincode,
        qualification: cleanQual,
        experienceYears: experienceYears <= 0 ? 5 : experienceYears,
        languages: doctorLangs,
      ).then((res) async {
        if (res['success'] == true) {
          await syncClinicsFromApi();
          await syncDoctorsFromApi();
        }
      }).catchError((e) {
        debugPrint('Error syncing registered doctor/clinic to Supabase: $e');
      });
    }

    return newDoctor;
  }

  /// Awaited Clinic Dashboard doctor registration & Supabase persistence (supports multiple doctors per clinic)
  Future<Map<String, dynamic>> addDoctorToClinicAndPersist({
    ClinicModel? clinic,
    required String clinicName,
    required String name,
    required String phone,
    String email = '',
    required String specialty,
    String qualification = '',
    int experienceYears = 5,
    String licenseNumber = '',
    String consultationFee = '',
    String bio = '',
    String city = '',
    String pincode = '',
    List<String>? languages,
  }) async {
    final cleanSpecialty = specialty.trim().isEmpty ? 'General Medicine' : specialty.trim();
    final cleanQual = qualification.trim().isEmpty
        ? MedicalSpecialtyModel.getDefaultQualificationForSpecialty(cleanSpecialty)
        : qualification.trim();
    final targetClinic = clinic ?? resolveClinic(explicitClinicName: clinicName);
    final resolvedClinicId = targetClinic?.id ?? '';
    final resolvedClinicName = (targetClinic?.clinicName.trim().isNotEmpty == true)
        ? targetClinic!.clinicName.trim()
        : clinicName.trim();

    final res = await ApiService().addClinicDoctorApi(
      clinicId: resolvedClinicId,
      clinicName: resolvedClinicName,
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim().isEmpty ? null : email.trim(),
      specialty: cleanSpecialty,
      qualification: cleanQual,
      experienceYears: experienceYears,
      licenseNumber: licenseNumber.trim().isEmpty ? null : licenseNumber.trim(),
      consultationFee: consultationFee.trim().isEmpty ? null : consultationFee.trim(),
      bio: bio.trim().isEmpty ? null : bio.trim(),
      city: city.trim().isEmpty ? null : city.trim(),
      pincode: pincode.trim().isEmpty ? null : pincode.trim(),
      languages: languages,
    );

    if (res['success'] == true) {
      await syncClinicsFromApi();
      await syncDoctorsFromApi(includeUnavailable: true);
      if (targetClinic != null) {
        await fetchClinicDoctors(targetClinic);
      }
      final rawDoc = res['doctor'];
      DoctorModel? parsed;
      if (rawDoc is Map) {
        parsed = DoctorModel.fromJson(Map<String, dynamic>.from(rawDoc));
      }
      return {
        'success': true,
        'doctor': parsed,
        'message': res['message'] ?? 'Doctor added to clinic successfully.',
      };
    }

    return {
      'success': false,
      'message': (res['message'] ?? 'Failed to add doctor to clinic.').toString(),
    };
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
  final List<PatientReferral> _myCreatedPatientReferrals = [];
  final List<PatientReferral> _doctorReceivedPatientReferrals = [];
  final List<PatientReferral> _receivedForMePatientReferrals = [];
  final List<PatientReferral> _clinicPatientReferrals = [];
  List<PatientReferral> _adminPatientReferrals = [];

  List<ReferralItem> get myReferrals => _myReferrals;
  ReferralStats get myReferralStats => _myReferralStats;
  String get myReferralCode => _myReferralCode.isNotEmpty
      ? _myReferralCode
      : 'DG-${(currentPatient.name.isNotEmpty ? currentPatient.name.substring(0, currentPatient.name.length >= 3 ? 3 : currentPatient.name.length).toUpperCase() : "PAT")}${currentPatient.phone.isNotEmpty && currentPatient.phone.length >= 4 ? currentPatient.phone.substring(currentPatient.phone.length - 4) : "2026"}';
  List<ReferralItem> get adminReferrals => _adminReferrals;
  List<PatientReferral> get adminPatientReferrals => List.unmodifiable(_adminPatientReferrals);
  AdminReferralAnalytics get adminReferralAnalytics => _adminReferralAnalytics;

  void addTestAdminPatientReferral(PatientReferral ref) {
    _adminPatientReferrals.removeWhere((r) => r.id == ref.id);
    _adminPatientReferrals.add(ref);
    notifyListeners();
  }

  void addTestDoctorReceivedReferral(PatientReferral ref) {
    _doctorReceivedPatientReferrals.removeWhere((r) => r.id == ref.id);
    _doctorReceivedPatientReferrals.add(ref);
    notifyListeners();
  }

  void addTestClinicPatientReferral(PatientReferral ref) {
    _clinicPatientReferrals.removeWhere((r) => r.id == ref.id);
    _clinicPatientReferrals.add(ref);
    notifyListeners();
  }

  void addTestPatientReferral(PatientReferral ref, {bool asReceived = true}) {
    if (asReceived) {
      _receivedForMePatientReferrals.removeWhere((r) => r.id == ref.id);
      _receivedForMePatientReferrals.add(ref);
    } else {
      _myCreatedPatientReferrals.removeWhere((r) => r.id == ref.id);
      _myCreatedPatientReferrals.add(ref);
    }
    notifyListeners();
  }

  List<PatientReferral> get myCreatedPatientReferrals => List.unmodifiable(_myCreatedPatientReferrals);
  List<PatientReferral> get doctorReceivedPatientReferrals => List.unmodifiable(_doctorReceivedPatientReferrals);
  List<PatientReferral> get receivedForMePatientReferrals => List.unmodifiable(_receivedForMePatientReferrals);
  List<PatientReferral> get clinicPatientReferrals => List.unmodifiable(_clinicPatientReferrals);

  /// Sync Referrals routed to doctors of the logged-in clinic (Strict Multi-Clinic Isolation)
  Future<void> syncClinicReferralsFromApi({String? clinicId, String? clinicName}) async {
    try {
      final sess = SessionService().currentSession;
      final resolvedClinic = resolveClinic(explicitClinicName: clinicName);
      final effectiveId = (clinicId != null && clinicId.trim().isNotEmpty)
          ? clinicId.trim()
          : (resolvedClinic?.id.isNotEmpty == true
              ? resolvedClinic!.id
              : (_authenticatedClinicId.isNotEmpty
                  ? _authenticatedClinicId
                  : (sess?.userId ?? '')));
      final effectiveName = (clinicName != null && clinicName.trim().isNotEmpty)
          ? clinicName.trim()
          : (resolvedClinic?.clinicName.isNotEmpty == true
              ? resolvedClinic!.clinicName
              : _authenticatedClinicName);

      if (effectiveId.isEmpty && effectiveName.isEmpty) return;

      final rawList = await ApiService().fetchClinicPatientReferrals(
        clinicId: effectiveId,
        clinicName: effectiveName,
      );
      final Map<String, PatientReferral> parsedMap = {};
      for (final r in rawList) {
        if (r is! Map) continue;
        try {
          final pref = PatientReferral.fromJson(Map<String, dynamic>.from(r));
          if (pref.id.isNotEmpty) parsedMap[pref.id] = pref;
        } catch (_) {}
      }
      _clinicPatientReferrals
        ..clear()
        ..addAll(parsedMap.values);
      notifyListeners();
    } catch (e) {
      debugPrint('Error in syncClinicReferralsFromApi: $e');
    }
  }

  /// Sync Patient Referrals created by or received for the logged-in user
  Future<void> syncReferralsFromApi({String? overrideUserId}) async {
    try {
      final authUser = SupabaseService.safeCurrentUser;
      final sess = SessionService().currentSession;
      final doc = currentDoctor;
      final userId = overrideUserId ??
          (sess != null && sess.userId.trim().isNotEmpty
              ? sess.userId.trim()
              : (doc != null && doc.userId.isNotEmpty
                  ? doc.userId
                  : (currentPatient.id.isNotEmpty
                      ? currentPatient.id
                      : (doc != null && doc.id.isNotEmpty ? doc.id : authUser?.id))));
      final phone = currentPatient.phone.isNotEmpty
          ? currentPatient.phone
          : (doc != null && doc.phone.isNotEmpty
              ? doc.phone
              : (sess?.phone ?? ''));
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

      // 2. Fetch Patient Referrals created by this user
      final rawPatientRefs = await ApiService().fetchMyPatientReferrals(userId: userId);
      final Map<String, PatientReferral> createdMap = {};
      for (final r in rawPatientRefs) {
        try {
          final pref = PatientReferral.fromJson(Map<String, dynamic>.from(r));
          final key = pref.id.isNotEmpty ? pref.id : '${pref.referredPatientMobile}_${pref.doctorId}';
          createdMap[key] = pref;
        } catch (_) {}
      }
      if (rawPatientRefs.isNotEmpty) {
        _myCreatedPatientReferrals
          ..clear()
          ..addAll(createdMap.values);
      }

      // 3. Fetch referrals where this user is the referred patient
      final rawReceived = await ApiService().fetchReceivedPatientReferrals(patientId: userId, patientPhone: phone);
      final Map<String, PatientReferral> receivedMap = {};
      for (final r in rawReceived) {
        try {
          final pref = PatientReferral.fromJson(Map<String, dynamic>.from(r));
          final key = pref.id.isNotEmpty ? pref.id : '${pref.referredPatientMobile}_${pref.doctorId}';
          receivedMap[key] = pref;
        } catch (_) {}
      }
      if (rawReceived.isNotEmpty) {
        _receivedForMePatientReferrals
          ..clear()
          ..addAll(receivedMap.values);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error in syncReferralsFromApi: $e');
    }
  }

  Set<String> _currentDoctorStrictIds([String? explicitDoctorId]) {
    final authUser = SupabaseService.safeCurrentUser;
    final sess = SessionService().currentSession;
    final authEmail = (authUser?.email ?? sess?.email ?? '').trim().toLowerCase();
    final doc = currentDoctor;

    final doctorIds = <String>{
      if (explicitDoctorId != null && explicitDoctorId.trim().isNotEmpty) explicitDoctorId.trim(),
      if (doc?.id != null && doc!.id.trim().isNotEmpty) doc.id.trim(),
      if (doc?.userId != null && doc!.userId.trim().isNotEmpty) doc.userId.trim(),
      if (sess?.metadata['dentistId'] != null && sess!.metadata['dentistId'].toString().trim().isNotEmpty)
        sess.metadata['dentistId'].toString().trim(),
      if (sess?.metadata['userId'] != null && sess!.metadata['userId'].toString().trim().isNotEmpty)
        sess.metadata['userId'].toString().trim(),
      if (sess?.userId != null && sess!.userId.trim().isNotEmpty) sess.userId.trim(),
      if (authUser?.id != null && authUser!.id.trim().isNotEmpty) authUser.id.trim(),
    };

    for (final d in allDoctors) {
      final matchById = (d.id.isNotEmpty && doctorIds.contains(d.id.trim())) ||
          (d.userId.isNotEmpty && doctorIds.contains(d.userId.trim()));
      final matchByEmail = authEmail.isNotEmpty && d.email.isNotEmpty && d.email.trim().toLowerCase() == authEmail;
      if (matchById || matchByEmail) {
        if (d.id.trim().isNotEmpty) doctorIds.add(d.id.trim());
        if (d.userId.trim().isNotEmpty) doctorIds.add(d.userId.trim());
      }
    }
    return doctorIds;
  }

  /// Sync Referrals received strictly by the logged-in Doctor (Strict Doctor Isolation)
  Future<void> syncDoctorReferralsFromApi({String? doctorId}) async {
    try {
      final authUser = SupabaseService.safeCurrentUser;
      final sess = SessionService().currentSession;
      final authEmail = (authUser?.email ?? sess?.email ?? '').trim().toLowerCase();

      // Auto-resolve currentDoctor strictly by ID or email (never substring name or clinic)
      if (currentDoctor == null && (authEmail.isNotEmpty || (sess?.userId.isNotEmpty == true))) {
        final match = allDoctors.where((d) =>
          (authEmail.isNotEmpty && d.email.trim().toLowerCase() == authEmail) ||
          (d.id.isNotEmpty && (d.id == authUser?.id || d.id == sess?.userId || d.id == sess?.metadata['dentistId']?.toString())) ||
          (d.userId.isNotEmpty && (d.userId == authUser?.id || d.userId == sess?.userId || d.userId == sess?.metadata['userId']?.toString()))
        ).firstOrNull;
        if (match != null) {
          currentDoctor = match;
        }
      }

      final doctorIds = _currentDoctorStrictIds(doctorId);
      if (doctorIds.isEmpty) {
        if (_doctorReceivedPatientReferrals.isNotEmpty) {
          _doctorReceivedPatientReferrals.clear();
          notifyListeners();
        }
        return;
      }

      final Map<String, PatientReferral> resultMap = {};
      bool anyFetchSucceeded = false;

      // Primary doctor referrals fetch exclusively from /referrals/doctor for the authenticated doctor
      final uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      final queryIds = doctorIds.where((id) => uuidPattern.hasMatch(id)).take(2).toList();
      if (queryIds.isEmpty) {
        queryIds.add(doctorIds.first);
      }

      for (final qId in queryIds) {
        try {
          final resp = await ApiService().fetchDoctorPatientReferralsWithStatus(doctorId: qId);
          if (resp.succeeded) {
            anyFetchSucceeded = true;
            for (final r in resp.referrals) {
              if (r is! Map) continue;
              try {
                final pref = PatientReferral.fromJson(Map<String, dynamic>.from(r));
                final refDocId = pref.doctorId.trim();
                // Double-check doctor ownership: never accept referrals belonging to another doctor
                if (refDocId.isNotEmpty && !doctorIds.contains(refDocId)) continue;
                if (pref.id.isNotEmpty) resultMap[pref.id] = pref;
              } catch (_) {}
            }
            if (resultMap.isNotEmpty) break;
          }
        } catch (_) {}
      }

      if (anyFetchSucceeded) {
        _doctorReceivedPatientReferrals
          ..clear()
          ..addAll(resultMap.values);
        notifyListeners();
      } else {
        // Offline / test fallback: still purge any cached referral that does not belong to this doctor
        final beforeLen = _doctorReceivedPatientReferrals.length;
        _doctorReceivedPatientReferrals.removeWhere(
          (r) => r.doctorId.trim().isNotEmpty && !doctorIds.contains(r.doctorId.trim()),
        );
        if (_doctorReceivedPatientReferrals.length != beforeLen) {
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error in syncDoctorReferralsFromApi: $e');
    }
  }

  /// Get patients associated with the currently logged-in dentist (excluding unrelated patients)
  List<PatientProfile> getDentistAssociatedPatients() {
    var doc = currentDoctor;
    final authUser = SupabaseService.safeCurrentUser;
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
      if (myDoctorIds.isEmpty && docNameClean.isEmpty) return false;
      final aId = r.assignedDoctorId?.trim();
      if (aId != null && aId.isNotEmpty) {
        return myDoctorIds.contains(aId);
      }
      final aName = r.assignedDoctorName?.replaceAll(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim().toLowerCase();
      if (docNameClean.isNotEmpty && aName != null && aName.isNotEmpty && aName == docNameClean) {
        return true;
      }
      return false;
    }

    final Map<String, PatientProfile> associatedMap = {};

    // 1. From dentist assigned requests & timeline requests (strictly assigned to this doctor)
    final allPool = [
      ..._dentistAssignedRequests.where((r) => isAssignedToMe(r)),
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
        id: matchedProfile?.id.isNotEmpty == true ? matchedProfile!.id : (req.patientId?.isNotEmpty == true ? req.patientId! : req.id),
        name: req.patientName.trim(),
        phone: raw10.isNotEmpty ? raw10 : (matchedProfile?.phone.isNotEmpty == true ? matchedProfile!.phone : req.patientPhone),
        email: matchedProfile?.email.isNotEmpty == true ? matchedProfile!.email : '',
        age: matchedProfile?.age ?? '',
        gender: matchedProfile?.gender ?? '',
        city: req.city.isNotEmpty ? req.city : (matchedProfile?.city ?? ''),
        pincode: req.pincode.isNotEmpty ? req.pincode : (matchedProfile?.pincode ?? ''),
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
    String doctorId = '',
    String? referrerPatientId,
    String? doctorName,
    String? doctorClinicName,
    String? doctorLocation,
    String? doctorCity,
    String? doctorPincode,
    String? doctorPhone,
    bool sendWhatsApp = false,
  }) async {
    try {
      final authUser = SupabaseService.safeCurrentUser;
      final sess = SessionService().currentSession;
      final doc = currentDoctor;
      final referrerId = (referrerPatientId != null && referrerPatientId.isNotEmpty)
          ? referrerPatientId
          : ((doc != null && doc.userId.isNotEmpty)
              ? doc.userId
              : ((sess != null && sess.userId.isNotEmpty)
                  ? sess.userId
                  : (currentPatient.id.isNotEmpty
                      ? currentPatient.id
                      : (doc != null && doc.id.isNotEmpty ? doc.id : authUser?.id))));

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
        sendWhatsApp: sendWhatsApp,
      );

      if (res['success'] == true && res['referral'] != null) {
        try {
          final newRef = PatientReferral.fromJson(Map<String, dynamic>.from(res['referral']));
          _myCreatedPatientReferrals.removeWhere((r) => r.id == newRef.id);
          _myCreatedPatientReferrals.insert(0, newRef);
          _adminPatientReferrals.removeWhere((r) => r.id == newRef.id);
          _adminPatientReferrals.insert(0, newRef);
          if (doc != null && (newRef.doctorId == doc.id || newRef.doctorId == doc.userId)) {
            _doctorReceivedPatientReferrals.removeWhere((r) => r.id == newRef.id);
            _doctorReceivedPatientReferrals.insert(0, newRef);
          }

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

  void _applyReferralStatusLocally(
    String referralId, {
    required String status,
    String? rejectionReason,
  }) {
    final pools = [
      _doctorReceivedPatientReferrals,
      _myCreatedPatientReferrals,
      _receivedForMePatientReferrals,
      _clinicPatientReferrals,
      _adminPatientReferrals,
    ];
    bool updatedAny = false;
    for (final list in pools) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == referralId) {
          final old = list[i];
          list[i] = PatientReferral(
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
            doctorPhone: old.doctorPhone,
            doctorLanguages: old.doctorLanguages,
            status: status,
            rejectionReason: status == 'Rejected' ? rejectionReason : null,
            whatsappStatus: old.whatsappStatus,
            referralDate: old.referralDate,
            createdAt: old.createdAt,
            updatedAt: DateTime.now(),
          );
          updatedAny = true;
        }
      }
    }
    if (updatedAny) {
      notifyListeners();
    }
  }

  bool _canCurrentRoleMutateReferralStatus() {
    final role = (SessionService().currentSession?.role ?? '').trim().toLowerCase();
    if (role == 'patient') return false;
    if (role == 'dentist' ||
        role == 'doctor' ||
        role == 'clinic' ||
        role == 'clinic_admin' ||
        role == 'admin' ||
        role == 'sub-admin' ||
        role == 'subadmin' ||
        role == 'superadmin') {
      return true;
    }
    return _isDentistMode ||
        _isClinicMode ||
        _isAdminMode ||
        _isSubAdminMode ||
        currentDoctor != null;
  }

  /// Doctor Accepts Referral
  Future<bool> acceptPatientReferralByDoctor(String referralId, {String? confirmedTimeSlot}) async {
    if (!_canCurrentRoleMutateReferralStatus()) {
      debugPrint('Blocked referral accept attempt from non-doctor/patient session.');
      return false;
    }
    try {
      final res = await ApiService().acceptPatientReferral(referralId, confirmedTimeSlot: confirmedTimeSlot);
      if (res['success'] == true) {
        _applyReferralStatusLocally(referralId, status: 'Accepted');
        return true;
      }
    } catch (e) {
      debugPrint('Error accepting referral: $e');
    }
    return false;
  }

  /// Doctor Rejects Referral
  Future<bool> rejectPatientReferralByDoctor(String referralId, {String? rejectionReason}) async {
    if (!_canCurrentRoleMutateReferralStatus()) {
      debugPrint('Blocked referral reject attempt from non-doctor/patient session.');
      return false;
    }
    try {
      final res = await ApiService().rejectPatientReferral(referralId, rejectionReason: rejectionReason);
      if (res['success'] == true) {
        _applyReferralStatusLocally(referralId, status: 'Rejected', rejectionReason: rejectionReason);
        return true;
      }
    } catch (e) {
      debugPrint('Error rejecting referral: $e');
    }
    return false;
  }

  /// Update Patient Referral status across all 5 statuses (Pending, Accepted, Rejected, Contacted, Completed)
  Future<bool> updatePatientReferralStatus(
    String referralId, {
    required String status,
    String? reason,
  }) async {
    if (!_canCurrentRoleMutateReferralStatus()) {
      debugPrint('Blocked referral status update attempt from non-doctor/patient session.');
      return false;
    }
    try {
      final res = await ApiService().updatePatientReferralStatus(referralId, status: status, reason: reason);
      if (res['success'] == true) {
        _applyReferralStatusLocally(referralId, status: status, rejectionReason: reason);
        return true;
      }
    } catch (e) {
      debugPrint('Error updating referral status: $e');
    }
    return false;
  }

  /// Delete a Patient Referral
  Future<bool> deletePatientReferral(String referralId) async {
    try {
      _myCreatedPatientReferrals.removeWhere((r) => r.id == referralId);
      _doctorReceivedPatientReferrals.removeWhere((r) => r.id == referralId);
      _receivedForMePatientReferrals.removeWhere((r) => r.id == referralId);
      _clinicPatientReferrals.removeWhere((r) => r.id == referralId);
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
        final seenRefIds = <String>{};
        final uniqueRaw = <Map<String, dynamic>>[];
        for (final r in list) {
          if (r is! Map) continue;
          final map = Map<String, dynamic>.from(r);
          final id = (map['id'] ?? map['_id'] ?? '').toString().trim();
          if (id.isNotEmpty && !seenRefIds.add(id)) continue;
          uniqueRaw.add(map);
        }
        _adminPatientReferrals = uniqueRaw
            .map((r) => PatientReferral.fromJson(r))
            .toList();
        _adminReferrals = uniqueRaw
            .map((r) => ReferralItem.fromJson(r))
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

  /// Returns notifications filtered for the given role & currently logged-in user
  List<AppNotificationModel> getNotificationsForRole(String role, {String? clinicId, String? clinicName}) {
    final normRole = role.trim().toLowerCase();
    final isAdminRole = normRole == 'admin' || normRole == 'sub-admin' || normRole == 'subadmin';
    final isDoctorRole = normRole == 'dentist' || normRole == 'doctor';
    final isClinicRole = normRole == 'clinic' || normRole == 'clinic_admin';
    final isPatientRole = normRole == 'patient';

    final sess = SessionService().currentSession;
    final candidateIds = <String>{
      if (sess != null && sess.userId.trim().isNotEmpty) sess.userId.trim(),
      if (_safeAuthUserId != null && _safeAuthUserId!.trim().isNotEmpty) _safeAuthUserId!.trim(),
    };

    if (isDoctorRole) {
      if (currentDoctor != null) {
        if (currentDoctor!.id.isNotEmpty) candidateIds.add(currentDoctor!.id);
        if (currentDoctor!.userId.isNotEmpty) candidateIds.add(currentDoctor!.userId);
        if (currentDoctor!.name.isNotEmpty) candidateIds.add(currentDoctor!.name);
      }
      for (final d in _allDoctors) {
        if (candidateIds.contains(d.id) || (d.userId.isNotEmpty && candidateIds.contains(d.userId))) {
          if (d.id.isNotEmpty) candidateIds.add(d.id);
          if (d.userId.isNotEmpty) candidateIds.add(d.userId);
        }
      }
    } else if (isClinicRole) {
      final resolved = resolveClinic(explicitClinicName: clinicName);
      if (clinicId != null && clinicId.trim().isNotEmpty) candidateIds.add(clinicId.trim());
      if (_authenticatedClinicId.isNotEmpty) candidateIds.add(_authenticatedClinicId);
      if (resolved != null) {
        if (resolved.id.isNotEmpty) candidateIds.add(resolved.id);
        if (resolved.userId.isNotEmpty) candidateIds.add(resolved.userId);
        if (resolved.clinicName.isNotEmpty) candidateIds.add(resolved.clinicName);
      }
      if (clinicName != null && clinicName.trim().isNotEmpty) candidateIds.add(clinicName.trim());
      if (_authenticatedClinicName.isNotEmpty) candidateIds.add(_authenticatedClinicName);
    } else if (isPatientRole) {
      if (currentPatient.id.isNotEmpty) candidateIds.add(currentPatient.id);
      if (currentPatient.name.isNotEmpty) candidateIds.add(currentPatient.name);
    } else if (isAdminRole) {
      if (_subAdminId.isNotEmpty) candidateIds.add(_subAdminId);
      candidateIds.add('ALL_ADMINS');
    }

    final candidateLower = candidateIds.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();

    return _appNotifications.where((n) {
      final nRole = n.recipientRole.trim().toLowerCase();
      final nRec = n.recipientId.trim();
      final nRecLower = nRec.toLowerCase();
      final nRecUpper = nRec.toUpperCase();

      if (isAdminRole) {
        return nRole == 'admin' ||
            nRole == 'sub-admin' ||
            nRecUpper == 'ALL_ADMINS' ||
            (nRole == 'all' && (nRecUpper == 'ALL' || nRecUpper == 'ALL_ADMINS'));
      }
      if (isDoctorRole) {
        final roleMatch = nRole == 'dentist' || nRole == 'doctor' || nRole == 'all';
        if (!roleMatch) return false;
        if (nRecUpper == 'ALL') return true;
        if (candidateIds.isEmpty) return false;
        return candidateIds.contains(nRec);
      }
      if (isClinicRole) {
        final roleMatch = nRole == 'clinic' || nRole == 'clinic_admin' || nRole == 'all';
        if (!roleMatch) return false;
        if (nRecUpper == 'ALL_CLINICS') return true;
        if (candidateLower.isEmpty) return false;
        return candidateLower.contains(nRecLower);
      }
      if (isPatientRole) {
        final roleMatch = nRole == 'patient' || nRole == 'all';
        if (!roleMatch) return false;
        if (nRecUpper == 'ALL' || candidateIds.isEmpty) return true;
        return candidateIds.contains(nRec);
      }
      return nRole == normRole || candidateIds.contains(nRec);
    }).toList();
  }

  /// Sync In-App Notifications from DB & synthesize dynamic consultation/referral alerts
  Future<void> syncNotificationsFromApi({String? role, String? userId}) async {
    try {
      final authUser = SupabaseService.safeCurrentUser;
      final sess = SessionService().currentSession;
      final sessRole = (sess?.role ?? '').trim();

      final effectiveRole = (role != null && role.trim().isNotEmpty)
          ? role.trim()
          : (_isAdminMode || _isSubAdminMode || sessRole.toLowerCase().contains('admin')
              ? 'Admin'
              : ((_isClinicMode || sessRole.toLowerCase().contains('clinic'))
                  ? 'Clinic'
                  : ((_isDentistMode || currentDoctor != null || sessRole.toLowerCase() == 'dentist' || sessRole.toLowerCase() == 'doctor')
                      ? 'Dentist'
                      : 'Patient')));

      String? effectiveUserId = userId;
      if (effectiveUserId == null || effectiveUserId.trim().isEmpty) {
        if (effectiveRole == 'Dentist' || effectiveRole == 'Doctor') {
          effectiveUserId = (currentDoctor?.id.isNotEmpty == true)
              ? currentDoctor!.id
              : ((currentDoctor?.userId.isNotEmpty == true)
                  ? currentDoctor!.userId
                  : (sess?.userId ?? authUser?.id));
        } else if (effectiveRole == 'Clinic' || effectiveRole == 'clinic_admin') {
          final resolved = resolveClinic();
          effectiveUserId = (resolved != null && resolved.id.isNotEmpty)
              ? resolved.id
              : (_authenticatedClinicId.isNotEmpty
                  ? _authenticatedClinicId
                  : (sess?.userId ?? authUser?.id));
        } else if (effectiveRole == 'Admin' || effectiveRole == 'Sub-Admin') {
          effectiveUserId = _subAdminId.isNotEmpty ? _subAdminId : (sess?.userId ?? authUser?.id);
        } else {
          effectiveUserId = currentPatient.id.isNotEmpty ? currentPatient.id : (sess?.userId ?? authUser?.id);
        }
      }

      final rawList = await _api.fetchNotifications(
        role: effectiveRole,
        userId: effectiveUserId,
      );

      final Map<String, AppNotificationModel> notifMap = {};

      // 1. Keep notifications belonging to other roles/sessions or local-only alerts
      for (final n in _appNotifications) {
        if (n.id.isNotEmpty) notifMap[n.id] = n;
      }

      // 2. Add/update API notifications from DB (authoritative read status from Supabase)
      for (final item in rawList) {
        try {
          final id = item['id']?.toString() ?? 'NOTIF-${DateTime.now().millisecondsSinceEpoch}';
          final rRole = item['recipient_role']?.toString() ?? effectiveRole;
          final rId = item['recipient_id']?.toString() ?? item['user_id']?.toString() ?? '';
          final title = item['title']?.toString() ?? 'GS HEALTH Notification';
          final message = item['message']?.toString() ?? '';
          final isRead = item['read'] == true || item['is_read'] == true;
          final ts = item['created_at'] != null
              ? (DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now())
              : DateTime.now();

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
      // Deduplicate notifications with identical role, recipient, title, and message within the same minute
      final seenKeys = <String>{};
      for (final n in sortedList) {
        final minuteBucket = n.timestamp.toIso8601String().substring(0, 16);
        final key = '${n.recipientRole}|${n.recipientId}|${n.title}|${n.message}|$minuteBucket';
        if (seenKeys.contains(key)) continue;
        seenKeys.add(key);
        _appNotifications.add(n);
      }
      _saveToStorage();
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
      await _api.markNotificationAsRead(notifId);
    }
  }

  /// Mark all notifications as read for a given role
  Future<void> markAllNotificationsRead(String role) async {
    final targetNotifs = getNotificationsForRole(role);
    for (final n in targetNotifs) {
      if (!n.isRead) {
        n.isRead = true;
        _api.markNotificationAsRead(n.id);
      }
    }
    notifyListeners();
    _saveToStorage();

    final sess = SessionService().currentSession;
    String? effectiveUserId;
    if (role.toLowerCase() == 'dentist' || role.toLowerCase() == 'doctor') {
      effectiveUserId = currentDoctor?.id.isNotEmpty == true
          ? currentDoctor!.id
          : (currentDoctor?.userId.isNotEmpty == true ? currentDoctor!.userId : sess?.userId);
    } else if (role.toLowerCase().contains('admin')) {
      effectiveUserId = _subAdminId.isNotEmpty ? _subAdminId : sess?.userId;
    } else {
      effectiveUserId = currentPatient.id.isNotEmpty ? currentPatient.id : sess?.userId;
    }
    await _api.markAllNotificationsAsRead(role: role, userId: effectiveUserId);
  }

  // ─────────────────────────────────────────────
  // DOCTOR AVAILABILITY STATE & API INTEGRATION
  // ─────────────────────────────────────────────
  final Map<String, DoctorAvailabilityModel> _availabilityCache = {};
  final Map<String, DoctorScheduleModel> _doctorScheduleCache = {};
  final Map<String, List<DoctorAvailabilityModel>> _blockedDatesCache = {};

  DoctorAvailabilityModel? getCachedAvailability(String doctorId, String dateStr) {
    return _availabilityCache['${doctorId}_$dateStr'];
  }

  DoctorScheduleModel? getCachedDoctorSchedule(String doctorId) {
    return _doctorScheduleCache[doctorId];
  }

  List<DoctorAvailabilityModel> getCachedBlockedDates(String doctorId) {
    return List.unmodifiable(_blockedDatesCache[doctorId] ?? const []);
  }

  /// Test hook: inject/seed availability record in widget tests without live backend
  @visibleForTesting
  void setTestAvailability(String doctorId, DoctorAvailabilityModel avail) {
    final dStr = avail.date.contains('T') ? avail.date.split('T').first : avail.date;
    _availabilityCache['${doctorId}_$dStr'] = avail;
    final current = List<DoctorAvailabilityModel>.from(_blockedDatesCache[doctorId] ?? const []);
    current.removeWhere((b) => b.date == dStr);
    if (avail.isBlocked) {
      current.add(avail);
      current.sort((a, b) => a.date.compareTo(b.date));
    }
    _blockedDatesCache[doctorId] = current;
    notifyListeners();
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

    final hasBreakRaw = breakStartTime != null && breakEndTime != null && breakStartTime.trim().isNotEmpty && breakEndTime.trim().isNotEmpty;
    final breakStart = hasBreakRaw ? timeToMinutes(breakStartTime) : -1;
    final breakEnd = hasBreakRaw ? timeToMinutes(breakEndTime) : -1;
    final hasBreak = hasBreakRaw && breakEnd > breakStart;

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

  String _formatYmdLocal(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Fetch persisted weekly schedule + blocked dates for a doctor
  Future<DoctorScheduleModel> getDoctorSchedule(String doctorId) async {
    if (doctorId.trim().isEmpty) return const DoctorScheduleModel();
    try {
      final res = await _api.fetchDoctorSchedule(dentistId: doctorId);
      if (res['success'] == true) {
        if (res['blockedDates'] is List) {
          final parsedBlocked = <DoctorAvailabilityModel>[];
          final seenDates = <String>{};
          for (final item in (res['blockedDates'] as List)) {
            if (item is Map) {
              final model = DoctorAvailabilityModel.fromJson(Map<String, dynamic>.from(item));
              final dKey = model.date.split('T').first;
              if (dKey.isNotEmpty && !seenDates.contains(dKey)) {
                seenDates.add(dKey);
                parsedBlocked.add(model.copyWith(date: dKey, isBlocked: true));
              }
            }
          }
          parsedBlocked.sort((a, b) => a.date.compareTo(b.date));
          _blockedDatesCache[doctorId] = parsedBlocked;
        }
        if (res['schedule'] is Map) {
          final schedule = DoctorScheduleModel.fromJson(Map<String, dynamic>.from(res['schedule'] as Map));
          _doctorScheduleCache[doctorId] = schedule;
          notifyListeners();
          return schedule;
        }
      }
    } catch (e) {
      debugPrint('getDoctorSchedule notice: $e');
    }
    return _doctorScheduleCache[doctorId] ?? const DoctorScheduleModel();
  }

  /// Fetch all blocked dates / holidays for a doctor
  Future<List<DoctorAvailabilityModel>> getBlockedDates(String doctorId) async {
    if (doctorId.trim().isEmpty) return const [];
    try {
      final res = await _api.fetchBlockedDates(dentistId: doctorId);
      if (res['success'] == true && res['blockedDates'] is List) {
        final out = <DoctorAvailabilityModel>[];
        final seen = <String>{};
        for (final item in (res['blockedDates'] as List)) {
          if (item is Map) {
            final model = DoctorAvailabilityModel.fromJson(Map<String, dynamic>.from(item));
            final cleanDate = model.date.split('T').first;
            if (cleanDate.isNotEmpty && !seen.contains(cleanDate)) {
              seen.add(cleanDate);
              out.add(model.copyWith(date: cleanDate, isBlocked: true));
              _availabilityCache['${doctorId}_$cleanDate'] = model.copyWith(
                date: cleanDate,
                isBlocked: true,
                availableSlots: const [],
              );
            }
          }
        }
        out.sort((a, b) => a.date.compareTo(b.date));
        _blockedDatesCache[doctorId] = out;
        notifyListeners();
        return out;
      }
    } catch (e) {
      debugPrint('getBlockedDates notice: $e');
    }
    return _blockedDatesCache[doctorId] ?? const [];
  }

  /// Fetch all configured availability records for a doctor across dates
  Future<List<DoctorAvailabilityModel>> getDoctorConfiguredAvailabilities(String doctorId) async {
    try {
      final res = await _api.fetchDoctorAvailability(dentistId: doctorId);
      if (res['success'] == true) {
        if (res['schedule'] is Map) {
          _doctorScheduleCache[doctorId] = DoctorScheduleModel.fromJson(Map<String, dynamic>.from(res['schedule'] as Map));
        }
        if (res['availabilities'] is List) {
          final list = <DoctorAvailabilityModel>[];
          final blockedList = <DoctorAvailabilityModel>[];
          final seenBlocked = <String>{};
          for (final item in (res['availabilities'] as List)) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              final rawSlots = map['slots'] ?? map['allSlots'] ?? [];
              final allSlots = rawSlots is List
                  ? rawSlots.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
                  : <String>[];
              final isBlocked = map['is_blocked'] == true || map['isBlocked'] == true;
              final cleanDate = (map['date'] ?? '').toString().split('T').first;
              final model = DoctorAvailabilityModel(
                id: (map['id'] ?? '').toString(),
                dentistId: (map['dentist_id'] ?? map['dentistId'] ?? doctorId).toString(),
                date: cleanDate,
                dayOfWeek: (map['day_of_week'] ?? map['dayOfWeek'] ?? '').toString(),
                startTime: (map['start_time'] ?? map['startTime'] ?? '09:00 AM').toString(),
                endTime: (map['end_time'] ?? map['endTime'] ?? '05:00 PM').toString(),
                slotDurationMinutes: int.tryParse((map['slot_duration_minutes'] ?? map['slotDurationMinutes'] ?? '30').toString()) ?? 30,
                allSlots: allSlots,
                bookedSlots: const [],
                availableSlots: isBlocked ? const [] : allSlots,
                isBlocked: isBlocked,
                blockedReason: (map['blocked_reason'] ?? map['blockedReason'])?.toString(),
              );
              list.add(model);
              if (cleanDate.isNotEmpty) {
                if (isBlocked && !seenBlocked.contains(cleanDate)) {
                  seenBlocked.add(cleanDate);
                  blockedList.add(model);
                }
              }
            }
          }
          blockedList.sort((a, b) => a.date.compareTo(b.date));
          _blockedDatesCache[doctorId] = blockedList;
          return list;
        }
      }
    } catch (e) {
      debugPrint('getDoctorConfiguredAvailabilities notice: $e');
    }
    return [];
  }

  /// Get Doctor Availability for a specific date (DB / API is source of truth)
  Future<DoctorAvailabilityModel> getDoctorAvailability(
    String doctorId,
    DateTime date, {
    String consultationType = 'In-Person',
  }) async {
    final dateStr = _formatYmdLocal(date);
    final normMode = BookingRulesConfig.normalizeConsultationMode(consultationType);
    final cacheKey = '${doctorId}_${dateStr}_$normMode';

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
          final rDate = req.confirmedDate?.split('T').first ?? _formatYmdLocal(req.submittedAt);
          if (rDate == dateStr) {
            final slot = req.confirmedTimeSlot?.trim() ?? '';
            if (slot.isNotEmpty && !localBooked.any((b) => b.toLowerCase() == slot.toLowerCase())) {
              localBooked.add(slot);
            }
          }
        }
      }
    }

    try {
      final res = await _api.fetchDoctorAvailability(
        dentistId: doctorId,
        date: dateStr,
        consultationType: normMode,
      );
      if (res['schedule'] is Map) {
        _doctorScheduleCache[doctorId] = DoctorScheduleModel.fromJson(Map<String, dynamic>.from(res['schedule'] as Map));
      }
      if (res['success'] == true && res['availability'] != null) {
        final apiModel = DoctorAvailabilityModel.fromJson(Map<String, dynamic>.from(res['availability']));
        // Merge local booked slots with API booked slots
        final mergedBooked = <String>[...apiModel.bookedSlots];
        for (final lb in localBooked) {
          if (!mergedBooked.any((b) => b.toLowerCase() == lb.toLowerCase())) {
            mergedBooked.add(lb);
          }
        }

        // Database is the source of truth when API responds cleanly:
        // If blocked OR non-working day, slots are strictly empty.
        // If unblocked working day with custom or generated slots, compute availableSlots.
        List<String> resolvedAll = List<String>.from(apiModel.allSlots);
        if (!apiModel.isBlocked && apiModel.isWorkingDay && resolvedAll.isEmpty && res['hasCustomRecord'] != true) {
          // Direct Supabase fallback without record: generate using saved schedule if available
          final sched = _doctorScheduleCache[doctorId];
          final bStart = apiModel.breakStartTime ?? sched?.breakStartTime;
          final bEnd = apiModel.breakEndTime ?? sched?.breakEndTime;
          resolvedAll = generateTimeSlots(
            startTime: apiModel.startTime,
            endTime: apiModel.endTime,
            durationMinutes: apiModel.slotDurationMinutes,
            breakStartTime: apiModel.hasBreak ? bStart : null,
            breakEndTime: apiModel.hasBreak ? bEnd : null,
          );
        }

        final available = (apiModel.isBlocked || !apiModel.isWorkingDay)
            ? <String>[]
            : BookingRulesConfig.computeHybridAvailableSlots(
                date: date,
                slots: resolvedAll,
                consultationMode: normMode,
                occupiedIntervals: apiModel.occupiedIntervals,
                blockedIntervals: apiModel.blockedSlots,
                workingEndTime: apiModel.endTime,
                breakStartTime: apiModel.hasBreak ? (apiModel.breakStartTime ?? _doctorScheduleCache[doctorId]?.breakStartTime) : null,
                breakEndTime: apiModel.hasBreak ? (apiModel.breakEndTime ?? _doctorScheduleCache[doctorId]?.breakEndTime) : null,
              ).where((s) => !mergedBooked.any((b) => b.toLowerCase() == s.toLowerCase())).toList();

        final resolved = apiModel.copyWith(
          allSlots: resolvedAll,
          bookedSlots: mergedBooked,
          availableSlots: available,
        );
        _availabilityCache[cacheKey] = resolved;
        notifyListeners();
        return resolved;
      }
    } catch (e) {
      debugPrint('getDoctorAvailability api fetch notice: $e');
    }

    // Check if we have a cached model when network/API was unreachable
    final baseCacheKey = '${doctorId}_$dateStr';
    if (_availabilityCache.containsKey(cacheKey) || _availabilityCache.containsKey(baseCacheKey)) {
      final cached = (_availabilityCache[cacheKey] ?? _availabilityCache[baseCacheKey])!;
      final mergedBooked = <String>[...cached.bookedSlots];
      for (final lb in localBooked) {
        if (!mergedBooked.any((b) => b.toLowerCase() == lb.toLowerCase())) {
          mergedBooked.add(lb);
        }
      }
      final available = (cached.isBlocked || !cached.isWorkingDay)
          ? <String>[]
          : BookingRulesConfig.computeHybridAvailableSlots(
              date: date,
              slots: cached.allSlots,
              consultationMode: normMode,
              occupiedIntervals: cached.occupiedIntervals,
              blockedIntervals: cached.blockedSlots,
              workingEndTime: cached.endTime,
              breakStartTime: cached.hasBreak ? cached.breakStartTime : null,
              breakEndTime: cached.hasBreak ? cached.breakEndTime : null,
            ).where((s) => !mergedBooked.any((b) => b.toLowerCase() == s.toLowerCase())).toList();
      final updated = cached.copyWith(bookedSlots: mergedBooked, availableSlots: available);
      _availabilityCache[cacheKey] = updated;
      return updated;
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

    final sched = _doctorScheduleCache[doctorId];
    final timePattern = RegExp(r'^\d{1,2}:\d{2}\s*(AM|PM)$', caseSensitive: false);
    final validCustomSlots = doctor.nextAvailableSlots
        .map((s) => s.trim())
        .where((s) => timePattern.hasMatch(s))
        .toList();

    final List<String> defaultSlots = validCustomSlots.isNotEmpty
        ? validCustomSlots
        : generateTimeSlots(
            startTime: sched?.startTime ?? '09:00 AM',
            endTime: sched?.endTime ?? '05:00 PM',
            durationMinutes: sched?.slotDurationMinutes ?? 30,
            breakStartTime: (sched?.hasBreak ?? true) ? (sched?.breakStartTime ?? '01:00 PM') : null,
            breakEndTime: (sched?.hasBreak ?? true) ? (sched?.breakEndTime ?? '02:00 PM') : null,
          );

    final unbooked = defaultSlots.where((s) => !localBooked.any((b) => b.toLowerCase() == s.toLowerCase())).toList();
    final available = BookingRulesConfig.filterBookableSlotsForDate(date, unbooked);

    final fallbackModel = DoctorAvailabilityModel(
      dentistId: doctorId,
      date: dateStr,
      startTime: sched?.startTime ?? '09:00 AM',
      endTime: sched?.endTime ?? '05:00 PM',
      slotDurationMinutes: normMode == 'Online'
          ? (sched?.onlineDurationMinutes ?? BookingRulesConfig.durationForMode('Online'))
          : (sched?.inPersonDurationMinutes ?? sched?.slotDurationMinutes ?? 30),
      consultationType: normMode,
      consultationDurationMinutes: normMode == 'Online'
          ? (sched?.onlineDurationMinutes ?? BookingRulesConfig.durationForMode('Online'))
          : (sched?.inPersonDurationMinutes ?? BookingRulesConfig.durationForMode('In-Person')),
      bufferMinutes: normMode == 'Online'
          ? (sched?.onlineBufferMinutes ?? BookingRulesConfig.bufferForMode('Online'))
          : (sched?.inPersonBufferMinutes ?? BookingRulesConfig.bufferForMode('In-Person')),
      hasBreak: sched?.hasBreak ?? true,
      breakStartTime: sched?.breakStartTime,
      breakEndTime: sched?.breakEndTime,
      workingDays: sched?.workingDays ?? const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      allSlots: defaultSlots,
      bookedSlots: localBooked,
      availableSlots: available,
      isBlocked: false,
    );

    _availabilityCache[cacheKey] = fallbackModel;
    return fallbackModel;
  }

  /// Update persisted weekly & smart schedule (working days, hours, multiple breaks, Online/In-Person schedules, durations, buffers, daily limits)
  Future<Map<String, dynamic>> saveDoctorSchedule({
    required String doctorId,
    required List<String> workingDays,
    required String startTime,
    required String endTime,
    required int slotDurationMinutes,
    required bool hasBreak,
    String? breakStartTime,
    String? breakEndTime,
    List<Map<String, String>>? breaks,
    bool? inPersonEnabled,
    int? inPersonDurationMinutes,
    bool? onlineEnabled,
    int? onlineDurationMinutes,
    List<String>? onlineWorkingDays,
    String? onlineStartTime,
    String? onlineEndTime,
    int? inPersonBufferMinutes,
    int? onlineBufferMinutes,
    int? maxAppointmentsPerDay,
    bool? allowSimultaneousOnlineAndInPerson,
    Map<String, List<Map<String, dynamic>>>? blockedTimeRanges,
    List<String>? slots,
    bool applyToUpcomingDays = true,
  }) async {
    final res = await _api.updateDoctorSchedule(
      dentistId: doctorId,
      workingDays: workingDays,
      startTime: startTime,
      endTime: endTime,
      slotDurationMinutes: inPersonDurationMinutes ?? slotDurationMinutes,
      hasBreak: hasBreak,
      breakStartTime: breakStartTime,
      breakEndTime: breakEndTime,
      breaks: breaks,
      inPersonEnabled: inPersonEnabled,
      inPersonDurationMinutes: inPersonDurationMinutes,
      onlineEnabled: onlineEnabled,
      onlineDurationMinutes: onlineDurationMinutes,
      onlineWorkingDays: onlineWorkingDays,
      onlineStartTime: onlineStartTime,
      onlineEndTime: onlineEndTime,
      inPersonBufferMinutes: inPersonBufferMinutes,
      onlineBufferMinutes: onlineBufferMinutes,
      maxAppointmentsPerDay: maxAppointmentsPerDay,
      allowSimultaneousOnlineAndInPerson: allowSimultaneousOnlineAndInPerson,
      blockedTimeRanges: blockedTimeRanges,
      slots: slots,
      applyToUpcomingDays: applyToUpcomingDays,
    );
    if (res['success'] == true) {
      if (res['schedule'] is Map) {
        _doctorScheduleCache[doctorId] = DoctorScheduleModel.fromJson(Map<String, dynamic>.from(res['schedule'] as Map));
      } else {
        _doctorScheduleCache[doctorId] = DoctorScheduleModel(
          workingDays: workingDays,
          startTime: startTime,
          endTime: endTime,
          slotDurationMinutes: inPersonDurationMinutes ?? slotDurationMinutes,
          hasBreak: hasBreak,
          breakStartTime: hasBreak ? breakStartTime : null,
          breakEndTime: hasBreak ? breakEndTime : null,
          breaks: breaks ?? const [],
          inPersonEnabled: inPersonEnabled ?? true,
          inPersonDurationMinutes: inPersonDurationMinutes ?? slotDurationMinutes,
          onlineEnabled: onlineEnabled ?? true,
          onlineDurationMinutes: onlineDurationMinutes ?? 20,
          onlineWorkingDays: onlineWorkingDays,
          onlineStartTime: onlineStartTime,
          onlineEndTime: onlineEndTime,
          inPersonBufferMinutes: inPersonBufferMinutes ?? 10,
          onlineBufferMinutes: onlineBufferMinutes ?? 5,
          maxAppointmentsPerDay: maxAppointmentsPerDay,
          allowSimultaneousOnlineAndInPerson: allowSimultaneousOnlineAndInPerson ?? false,
          blockedTimeRanges: blockedTimeRanges ?? const {},
          isConfigured: true,
        );
      }
      // Invalidate date caches so Patient & Doctor screens re-read updated slots
      _availabilityCache.removeWhere((k, _) => k.startsWith('${doctorId}_'));
      notifyListeners();
    }
    return res;
  }

  /// Acquire a temporary slot lock for secure atomic booking
  Future<Map<String, dynamic>> acquireSlotLock({
    required String dentistId,
    required DateTime date,
    required String timeSlot,
    String consultationType = 'In-Person',
    String? releasedSlotId,
    int ttlSeconds = 300,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {
        'success': false,
        'reason': 'AUTH_REQUIRED',
        'message': 'Please sign in to reserve a time slot.',
      };
    }
    return _api.acquireSlotLock(
      dentistId: dentistId,
      patientId: pId,
      date: _formatYmdLocal(date),
      timeSlot: timeSlot,
      consultationType: consultationType,
      releasedSlotId: releasedSlotId,
      ttlSeconds: ttlSeconds,
    );
  }

  /// Release an active slot lock
  Future<void> releaseSlotLock(String lockId) async {
    if (lockId.trim().isEmpty) return;
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    await _api.releaseSlotLock(lockId: lockId, patientId: pId.isNotEmpty ? pId : null);
  }

  /// Test helper: seed cached availability for deterministic widget testing
  void seedAvailabilityForTest(
    String doctorId,
    DateTime date,
    DoctorAvailabilityModel availability, {
    String? consultationType,
  }) {
    final dateStr = _formatYmdLocal(date);
    final mode = BookingRulesConfig.normalizeConsultationMode(
      consultationType ?? availability.consultationType,
    );
    _availabilityCache['${doctorId}_${dateStr}_$mode'] = availability;
    _availabilityCache['${doctorId}_$dateStr'] = availability;
    notifyListeners();
  }

  /// Fetch patient notification preference for a specific doctor
  Future<PatientDoctorPreferenceModel?> getPatientDoctorPreference(String dentistId) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty || dentistId.trim().isEmpty) return null;
    final res = await _api.fetchPatientDoctorPreferences(patientId: pId, dentistId: dentistId);
    if (res['success'] == true && res['preferences'] is List) {
      final list = res['preferences'] as List;
      if (list.isNotEmpty && list.first is Map) {
        return PatientDoctorPreferenceModel.fromJson(Map<String, dynamic>.from(list.first as Map));
      }
    }
    return null;
  }

  /// Save patient favorite & earlier-slot notification preference for a doctor
  Future<Map<String, dynamic>> savePatientDoctorPreference({
    required String dentistId,
    required bool isFavorite,
    required bool notifyEarlierSlots,
    String preferredConsultationType = 'Any',
    String? preferredDate,
    int? earliestTimeMin,
    int? latestTimeMin,
  }) async {
    final pId = currentPatient.id.isNotEmpty ? currentPatient.id : (_safeAuthUserId ?? '');
    if (pId.isEmpty) {
      return {'success': false, 'message': 'Sign in to save earlier-slot alerts.'};
    }
    return _api.upsertPatientDoctorPreference(
      patientId: pId,
      dentistId: dentistId,
      isFavorite: isFavorite,
      notifyEarlierSlots: notifyEarlierSlots,
      preferredConsultationType: preferredConsultationType,
      preferredDate: preferredDate,
      earliestTimeMin: earliestTimeMin,
      latestTimeMin: latestTimeMin,
    );
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
    bool hasBreak = true,
    String? breakStartTime,
    String? breakEndTime,
    List<String>? workingDays,
    bool isBlocked = false,
    String? blockedReason,
    String dayOfWeek = '',
  }) async {
    final dateStr = _formatYmdLocal(date);
    final formattedBatchDates = batchDates?.map(_formatYmdLocal).toList();

    final res = await _api.saveDoctorAvailability(
      dentistId: doctorId,
      date: dateStr,
      dates: formattedBatchDates,
      slots: slots,
      startTime: startTime,
      endTime: endTime,
      slotDurationMinutes: slotDurationMinutes,
      hasBreak: hasBreak,
      breakStartTime: breakStartTime,
      breakEndTime: breakEndTime,
      workingDays: workingDays,
      isBlocked: isBlocked,
      blockedReason: blockedReason,
      dayOfWeek: dayOfWeek,
    );

    if (res['success'] == true) {
      if (res['schedule'] is Map) {
        _doctorScheduleCache[doctorId] = DoctorScheduleModel.fromJson(Map<String, dynamic>.from(res['schedule'] as Map));
      }
      _availabilityCache.removeWhere((k, _) => k.startsWith('${doctorId}_'));
      await getDoctorAvailability(doctorId, date);
      await getBlockedDates(doctorId);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Toggle Date Blocked ON / OFF (Immediate DB Persistence + Multi-Date Support)
  Future<Map<String, dynamic>> toggleBlockedDate({
    required String doctorId,
    required DateTime date,
    List<DateTime>? dates,
    required bool isBlocked,
    String reason = 'Doctor on Leave / Clinic Closed',
  }) async {
    final dateStr = _formatYmdLocal(date);
    final extraDates = dates?.map(_formatYmdLocal).toList();

    final res = await _api.blockDoctorDate(
      dentistId: doctorId,
      date: dateStr,
      dates: extraDates,
      reason: reason,
      isBlocked: isBlocked,
    );

    if (res['success'] == true) {
      final targets = (extraDates != null && extraDates.isNotEmpty) ? extraDates : [dateStr];
      final currentBlocked = List<DoctorAvailabilityModel>.from(_blockedDatesCache[doctorId] ?? const []);

      for (final dStr in targets) {
        _availabilityCache.remove('${doctorId}_$dStr');
        currentBlocked.removeWhere((b) => b.date == dStr);
        if (isBlocked) {
          currentBlocked.add(DoctorAvailabilityModel(
            dentistId: doctorId,
            date: dStr,
            isBlocked: true,
            blockedReason: reason,
            allSlots: const [],
            availableSlots: const [],
          ));
        }
      }
      currentBlocked.sort((a, b) => a.date.compareTo(b.date));
      _blockedDatesCache[doctorId] = currentBlocked;

      if (res['blockedDates'] is List) {
        final serverBlocked = <DoctorAvailabilityModel>[];
        final seen = <String>{};
        for (final item in (res['blockedDates'] as List)) {
          if (item is Map) {
            final m = DoctorAvailabilityModel.fromJson(Map<String, dynamic>.from(item));
            final cd = m.date.split('T').first;
            if (cd.isNotEmpty && !seen.contains(cd)) {
              seen.add(cd);
              serverBlocked.add(m.copyWith(date: cd, isBlocked: true));
            }
          }
        }
        serverBlocked.sort((a, b) => a.date.compareTo(b.date));
        _blockedDatesCache[doctorId] = serverBlocked;
      }

      await getDoctorAvailability(doctorId, date);
      notifyListeners();
    }
    return res;
  }

  /// Remove / Unblock a previously blocked date
  Future<Map<String, dynamic>> unblockDoctorDate({
    required String doctorId,
    required DateTime date,
  }) async {
    return toggleBlockedDate(doctorId: doctorId, date: date, isBlocked: false);
  }

  /// Block a doctor date (Backwards-compatible wrapper)
  Future<bool> blockDoctorDate({
    required String doctorId,
    required DateTime date,
    String reason = 'Doctor on Leave / Clinic Closed',
  }) async {
    final res = await toggleBlockedDate(
      doctorId: doctorId,
      date: date,
      isBlocked: true,
      reason: reason,
    );
    return res['success'] == true;
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

  Future<Map<String, dynamic>> updateDoctorProfessionalProfile({
    required String doctorId,
    String? name,
    String? phone,
    String? specialty,
    String? qualification,
    int? experienceYears,
    String? clinicName,
    String? clinicAddress,
    String? consultationFee,
    String? licenseNumber,
    String? status,
    String? verificationStatus,
    String? bio,
    String? city,
    String? state,
    String? pincode,
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    List<String>? languages,
    Uint8List? photoBytes,
    String? profilePhotoDataUri,
    String? profileImageUrl,
    bool removeProfilePhoto = false,
  }) async {
    int idx = _allDoctors.indexWhere((d) => d.id == doctorId || (d.userId.isNotEmpty && d.userId == doctorId));
    DoctorModel? baseDoc = idx != -1 ? _allDoctors[idx] : currentDoctor;
    if (baseDoc == null) {
      return {'success': false, 'message': 'Doctor profile not found.'};
    }

    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (specialty != null) 'specialty': specialty,
      if (qualification != null) 'qualification': qualification,
      if (experienceYears != null) 'experienceYears': experienceYears,
      if (clinicName != null) 'clinicName': clinicName,
      if (clinicAddress != null) 'clinicAddress': clinicAddress,
      if (state != null) 'state': state,
      if (pincode != null) 'pincode': pincode,
      if (clearLocation) 'clearLocation': true,
      if (!clearLocation && latitude != null && longitude != null) ...{
        'latitude': latitude,
        'longitude': longitude,
      },
      if (consultationFee != null) 'consultationFee': consultationFee,
      if (licenseNumber != null) 'licenseNumber': licenseNumber,
      if (status != null) 'status': status,
      if (verificationStatus != null) 'verificationStatus': verificationStatus,
      if (bio != null) 'bio': bio,
      if (city != null) 'city': city,
      if (languages != null) 'languages': languages,
      if (removeProfilePhoto) 'removeProfilePhoto': true,
      if (!removeProfilePhoto && profilePhotoDataUri != null && profilePhotoDataUri.trim().isNotEmpty)
        'profilePhoto': profilePhotoDataUri.trim()
      else if (!removeProfilePhoto && profileImageUrl != null && profileImageUrl.trim().isNotEmpty)
        'profilePhoto': profileImageUrl.trim(),
    };

    final apiRes = await ApiService().updateDoctorProfileWithResult(doctorId, payload);
    final apiCode = (apiRes['code'] ?? '').toString();
    if (apiRes['success'] != true && apiCode.startsWith('PROFILE_IMAGE_')) {
      return apiRes;
    }

    String? resolvedImageUrl = removeProfilePhoto ? null : (profileImageUrl ?? baseDoc.profileImageUrl);
    Uint8List? resolvedPhotoBytes = removeProfilePhoto ? null : (photoBytes ?? baseDoc.photoBytes);
    final returnedDoctor = apiRes['doctor'];
    if (returnedDoctor is Map && returnedDoctor.containsKey('profilePhoto')) {
      final parsed = DoctorModel.parseProfilePhoto(returnedDoctor['profilePhoto']);
      if (parsed.url != null && parsed.url!.isNotEmpty) {
        resolvedImageUrl = parsed.url;
      } else if (removeProfilePhoto) {
        resolvedImageUrl = null;
        resolvedPhotoBytes = null;
      }
      if (parsed.bytes != null && parsed.bytes!.isNotEmpty) {
        resolvedPhotoBytes = parsed.bytes;
      }
    }

    final updatedDoc = DoctorModel(
      id: baseDoc.id,
      userId: baseDoc.userId,
      clinicId: baseDoc.clinicId,
      name: name ?? baseDoc.name,
      specialty: specialty ?? baseDoc.specialty,
      qualification: qualification ?? baseDoc.qualification,
      experienceYears: experienceYears ?? baseDoc.experienceYears,
      rating: baseDoc.rating,
      reviewCount: baseDoc.reviewCount,
      clinicName: clinicName ?? baseDoc.clinicName,
      phone: phone ?? baseDoc.phone,
      email: baseDoc.email,
      status: status ?? baseDoc.status,
      onlineStatus: baseDoc.onlineStatus,
      verificationStatus: verificationStatus ?? baseDoc.verificationStatus,
      nextAvailableSlots: baseDoc.nextAvailableSlots,
      consultationFee: consultationFee ?? baseDoc.consultationFee,
      licenseNumber: licenseNumber ?? baseDoc.licenseNumber,
      photoBytes: resolvedPhotoBytes,
      profileImageUrl: resolvedImageUrl,
      clinicAddress: clinicAddress ?? baseDoc.clinicAddress,
      pincode: pincode ?? baseDoc.pincode,
      city: city ?? baseDoc.city,
      state: state ?? baseDoc.state,
      bio: bio ?? baseDoc.bio,
      languages: languages ?? baseDoc.languages,
      latitude: clearLocation ? null : (latitude ?? baseDoc.latitude),
      longitude: clearLocation ? null : (longitude ?? baseDoc.longitude),
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
    return {
      'success': apiRes['success'] == true || !apiCode.startsWith('PROFILE_IMAGE_'),
      'doctor': updatedDoc,
      if (apiRes['message'] != null) 'message': apiRes['message'],
    };
  }

  /// Toggle Doctor Availability ON/OFF persistently and update local + patient-facing state immediately.
  Future<Map<String, dynamic>> setDoctorAvailability({
    required String doctorId,
    required bool isAvailable,
    String? statusOverride,
  }) async {
    final newStatus = (statusOverride != null && statusOverride.trim().isNotEmpty)
        ? statusOverride.trim()
        : (isAvailable ? 'Available' : 'Unavailable');
    final int idx = _allDoctors.indexWhere((d) => d.id == doctorId || (d.userId.isNotEmpty && d.userId == doctorId));
    final DoctorModel? previousDoc = idx != -1 ? _allDoctors[idx] : currentDoctor;
    final String? previousStatus = previousDoc?.status;

    void applyStatusLocally(String statusToApply) {
      if (previousDoc == null) return;
      final updated = DoctorModel(
        id: previousDoc.id,
        userId: previousDoc.userId,
        name: previousDoc.name,
        specialty: previousDoc.specialty,
        qualification: previousDoc.qualification,
        experienceYears: previousDoc.experienceYears,
        rating: previousDoc.rating,
        reviewCount: previousDoc.reviewCount,
        clinicName: previousDoc.clinicName,
        phone: previousDoc.phone,
        email: previousDoc.email,
        status: statusToApply,
        verificationStatus: previousDoc.verificationStatus,
        nextAvailableSlots: previousDoc.nextAvailableSlots,
        consultationFee: previousDoc.consultationFee,
        licenseNumber: previousDoc.licenseNumber,
        photoBytes: previousDoc.photoBytes,
        profileImageUrl: previousDoc.profileImageUrl,
        clinicAddress: previousDoc.clinicAddress,
        pincode: previousDoc.pincode,
        city: previousDoc.city,
        state: previousDoc.state,
        bio: previousDoc.bio,
        languages: previousDoc.languages,
        latitude: previousDoc.latitude,
        longitude: previousDoc.longitude,
        procedureFees: previousDoc.procedureFees,
      );
      if (idx != -1) {
        _allDoctors[idx] = updated;
      }
      if (currentDoctor != null &&
          (currentDoctor!.id == doctorId ||
              currentDoctor!.userId == doctorId ||
              currentDoctor!.email.toLowerCase() == updated.email.toLowerCase())) {
        currentDoctor = updated;
      }
      _saveToStorage();
      notifyListeners();
    }

    // Optimistic local state update so UI reflects immediately
    applyStatusLocally(newStatus);

    final res = await ApiService().updateDoctorAvailability(
      doctorId,
      isAvailable,
      statusOverride: statusOverride,
    );
    if (res['success'] != true) {
      // Revert local state on backend failure
      if (previousStatus != null) {
        applyStatusLocally(previousStatus);
      }
      return res;
    }

    return res;
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
    if (clean.isEmpty) return const [];
    final matchedClinic = _allClinics
        .where((c) => c.clinicName.trim().toLowerCase() == clean)
        .firstOrNull;
    if (matchedClinic != null) {
      return getDoctorsForClinic(matchedClinic);
    }
    const genericPlaceholders = {
      '',
      'independent practice',
      'gs health partner clinic',
      'gs health medical center',
      'gs health practice',
      'gs health care clinic',
    };
    if (genericPlaceholders.contains(clean)) return const [];
    return _allDoctors.where((d) {
      final docClinic = d.clinicName.trim().toLowerCase();
      return docClinic.isNotEmpty && docClinic == clean;
    }).toList();
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

  // ─────────────────────────────────────────────
  // CLINIC DASHBOARD HELPERS, DETAILS, BOOKINGS & AD REQUESTS
  // ─────────────────────────────────────────────

  ClinicModel? resolveClinic({String? explicitClinicName}) {
    final targetName = (explicitClinicName ?? _authenticatedClinicName).trim().toLowerCase();
    final targetId = _authenticatedClinicId.trim();

    if (targetId.isNotEmpty) {
      final byId = _allClinics.where((c) => c.id == targetId || c.userId == targetId).firstOrNull;
      if (byId != null) return byId;
    }
    if (targetName.isNotEmpty) {
      final byName = _allClinics
          .where((c) => c.clinicName.trim().toLowerCase() == targetName)
          .firstOrNull;
      if (byName != null) return byName;
      final byContains = _allClinics
          .where((c) =>
              c.clinicName.trim().toLowerCase().contains(targetName) ||
              targetName.contains(c.clinicName.trim().toLowerCase()))
          .firstOrNull;
      if (byContains != null) return byContains;
    }
    return null;
  }

  Uint8List? clinicCoverBytesFor(String clinicId, String clinicName) {
    final idKey = clinicId.trim().toLowerCase();
    final nameKey = clinicName.trim().toLowerCase();
    return (idKey.isNotEmpty ? _clinicCoverBytesByKey[idKey] : null) ??
        (nameKey.isNotEmpty ? _clinicCoverBytesByKey[nameKey] : null) ??
        _authenticatedClinicCoverBytes;
  }

  String clinicCoverUrlFor(String clinicId, String clinicName, {String fallbackUrl = ''}) {
    final idKey = clinicId.trim().toLowerCase();
    final nameKey = clinicName.trim().toLowerCase();
    final cached = (idKey.isNotEmpty ? _clinicCoverUrlByKey[idKey] : null) ??
        (nameKey.isNotEmpty ? _clinicCoverUrlByKey[nameKey] : null);
    if (cached != null && cached.isNotEmpty) return cached;
    if (fallbackUrl.trim().isNotEmpty) return fallbackUrl.trim();
    if (_authenticatedClinicCoverUrl.trim().isNotEmpty &&
        (_authenticatedClinicId == clinicId ||
            _authenticatedClinicName.trim().toLowerCase() == nameKey)) {
      return _authenticatedClinicCoverUrl.trim();
    }
    return '';
  }

  bool isClinicFeaturedFor(String clinicId, String clinicName, {bool modelValue = false}) {
    final idKey = clinicId.trim().toLowerCase();
    final nameKey = clinicName.trim().toLowerCase();
    if (idKey.isNotEmpty && _clinicFeaturedByKey.containsKey(idKey)) {
      return _clinicFeaturedByKey[idKey] == true;
    }
    if (nameKey.isNotEmpty && _clinicFeaturedByKey.containsKey(nameKey)) {
      return _clinicFeaturedByKey[nameKey] == true;
    }
    if (modelValue) return true;
    if (_isClinicMode &&
        ((clinicId.isNotEmpty && _authenticatedClinicId == clinicId) ||
            (nameKey.isNotEmpty && _authenticatedClinicName.trim().toLowerCase() == nameKey))) {
      return _authenticatedClinicIsFeatured;
    }
    return false;
  }

  String clinicFeaturedPlanFor(String clinicId, String clinicName, {String modelValue = ''}) {
    final idKey = clinicId.trim().toLowerCase();
    final nameKey = clinicName.trim().toLowerCase();
    final cached = (idKey.isNotEmpty ? _clinicFeaturedPlanByKey[idKey] : null) ??
        (nameKey.isNotEmpty ? _clinicFeaturedPlanByKey[nameKey] : null);
    if (cached != null && cached.isNotEmpty) return cached;
    if (modelValue.trim().isNotEmpty) return modelValue.trim();
    return _authenticatedClinicFeaturedPlan;
  }

  List<DoctorModel> clinicDoctorsFor(String clinicName) {
    final cleanClinic = clinicName.trim().toLowerCase();
    if (cleanClinic.isEmpty) return const [];
    return _allDoctors.where((d) {
      final docClinic = d.clinicName.trim().toLowerCase();
      if (docClinic.isEmpty) return false;
      return docClinic == cleanClinic ||
          (cleanClinic.length > 3 && docClinic.contains(cleanClinic));
    }).toList();
  }

  List<PatientConsultationRequest> clinicBookingsFor({
    String? clinicId,
    required String clinicName,
  }) {
    final cleanClinic = clinicName.trim().toLowerCase();
    if (cleanClinic.isEmpty) return const [];

    final attachedDocs = clinicDoctorsFor(clinicName);
    final docIds = <String>{
      for (final d in attachedDocs) ...[
        if (d.id.trim().isNotEmpty) d.id.trim(),
        if (d.userId.trim().isNotEmpty) d.userId.trim(),
      ]
    };
    final docNames = <String>{
      for (final d in attachedDocs)
        if (d.name.trim().isNotEmpty)
          d.name.replaceAll('Dr.', '').trim().toLowerCase(),
    };

    final Map<String, PatientConsultationRequest> merged = {};
    for (final r in _requests) {
      merged[r.id] = r;
    }
    for (final r in _dentistAssignedRequests) {
      merged.putIfAbsent(r.id, () => r);
    }

    return merged.values.where((req) {
      final reqClinic = req.displayDoctorClinic.trim().toLowerCase();
      final prefClinic = (req.preferredDoctorClinic ?? '').trim().toLowerCase();
      final reqLoc = req.preferredLocation.trim().toLowerCase();
      final reqDocId = (req.assignedDoctorId ?? req.preferredDoctorId ?? '').trim();
      final reqDocName = (req.assignedDoctorName ?? req.preferredDoctorName ?? '')
          .replaceAll('Dr.', '')
          .trim()
          .toLowerCase();

      if (reqClinic == cleanClinic || prefClinic == cleanClinic) return true;
      if (cleanClinic.length > 3 &&
          (reqClinic.contains(cleanClinic) ||
              prefClinic.contains(cleanClinic) ||
              reqLoc.contains(cleanClinic))) {
        return true;
      }
      if (reqDocId.isNotEmpty && docIds.contains(reqDocId)) return true;
      if (reqDocName.isNotEmpty &&
          docNames.any((n) => reqDocName == n || reqDocName.contains(n) || n.contains(reqDocName))) {
        return true;
      }
      return false;
    }).toList();
  }

  List<PatientReferral> clinicReferralsFor({required String clinicName}) {
    final cleanClinic = clinicName.trim().toLowerCase();
    if (cleanClinic.isEmpty) return const [];

    final attachedDocs = clinicDoctorsFor(clinicName);
    final docIds = <String>{
      for (final d in attachedDocs) ...[
        if (d.id.trim().isNotEmpty) d.id.trim(),
        if (d.userId.trim().isNotEmpty) d.userId.trim(),
      ]
    };
    final docNames = <String>{
      for (final d in attachedDocs)
        if (d.name.trim().isNotEmpty)
          d.name.replaceAll('Dr.', '').trim().toLowerCase(),
    };

    final Map<String, PatientReferral> result = {};
    final pool = [
      ..._clinicPatientReferrals,
      ..._adminPatientReferrals,
      ..._doctorReceivedPatientReferrals,
    ];
    for (final ref in pool) {
      final refClinic = ref.doctorClinicName.trim().toLowerCase();
      final refDocId = ref.doctorId.trim();
      final refDocName = ref.doctorName.replaceAll('Dr.', '').trim().toLowerCase();
      final matchesClinic = refClinic.isNotEmpty &&
          (refClinic == cleanClinic ||
              (cleanClinic.length > 3 && refClinic.contains(cleanClinic)));
      final matchesDoc = (refDocId.isNotEmpty && docIds.contains(refDocId)) ||
          (refDocName.isNotEmpty &&
              docNames.any((n) => refDocName == n || refDocName.contains(n) || n.contains(refDocName)));
      if (matchesClinic || matchesDoc) {
        if (ref.id.isNotEmpty) {
          result[ref.id] = ref;
        }
      }
    }
    return result.values.toList();
  }

  Future<Map<String, dynamic>> updateClinicDetails({
    required String clinicId,
    required String clinicName,
    required String location,
    String? previousClinicName,
    String? coverImageUrl,
    Uint8List? coverImageBytes,
    bool? isFeatured,
    String? featuredPlan,
  }) async {
    final cleanName = clinicName.trim();
    final cleanLoc = location.trim();
    final prevName = (previousClinicName ?? _authenticatedClinicName).trim();

    if (cleanName.isNotEmpty) {
      _authenticatedClinicName = cleanName;
    }
    _authenticatedClinicLocation = cleanLoc;
    if (clinicId.trim().isNotEmpty) {
      _authenticatedClinicId = clinicId.trim();
    }
    if (coverImageUrl != null) {
      _authenticatedClinicCoverUrl = coverImageUrl.trim();
    }
    if (coverImageBytes != null) {
      _authenticatedClinicCoverBytes = coverImageBytes;
    }
    if (isFeatured != null) {
      _authenticatedClinicIsFeatured = isFeatured;
    }
    if (featuredPlan != null) {
      _authenticatedClinicFeaturedPlan = featuredPlan.trim();
    }

    final idKey = clinicId.trim().toLowerCase();
    final nameKey = cleanName.toLowerCase();
    final prevKey = prevName.toLowerCase();
    for (final key in {idKey, nameKey, prevKey}) {
      if (key.isEmpty) continue;
      if (coverImageBytes != null) _clinicCoverBytesByKey[key] = coverImageBytes;
      if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty) {
        _clinicCoverUrlByKey[key] = coverImageUrl.trim();
      }
      if (isFeatured != null) _clinicFeaturedByKey[key] = isFeatured;
      if (featuredPlan != null && featuredPlan.trim().isNotEmpty) {
        _clinicFeaturedPlanByKey[key] = featuredPlan.trim();
      }
    }

    int idx = _allClinics.indexWhere((c) =>
        (clinicId.trim().isNotEmpty && c.id == clinicId.trim()) ||
        (prevName.isNotEmpty && c.clinicName.trim().toLowerCase() == prevName.toLowerCase()) ||
        (cleanName.isNotEmpty && c.clinicName.trim().toLowerCase() == cleanName.toLowerCase()));

    String resolvedId = clinicId.trim();
    if (idx != -1) {
      final base = _allClinics[idx];
      resolvedId = base.id;
      _allClinics[idx] = ClinicModel(
        id: base.id,
        userId: base.userId,
        clinicName: cleanName.isNotEmpty ? cleanName : base.clinicName,
        location: cleanLoc,
        phone: base.phone,
        coverImageUrl: coverImageUrl != null ? coverImageUrl.trim() : base.coverImageUrl,
        isFeatured: isFeatured ?? base.isFeatured,
        featuredPlan: featuredPlan != null ? featuredPlan.trim() : base.featuredPlan,
        rating: base.rating,
        reviewsCount: base.reviewsCount,
        verified: base.verified,
        verificationStatus: base.verificationStatus,
        services: base.services,
        pricing: base.pricing,
      );
    } else if (cleanName.isNotEmpty) {
      resolvedId = resolvedId.isNotEmpty
          ? resolvedId
          : 'LOCAL-CLN-${DateTime.now().millisecondsSinceEpoch}';
      _authenticatedClinicId = resolvedId;
      _allClinics.insert(
        0,
        ClinicModel(
          id: resolvedId,
          clinicName: cleanName,
          location: cleanLoc,
          coverImageUrl: _authenticatedClinicCoverUrl,
          isFeatured: _authenticatedClinicIsFeatured,
          featuredPlan: _authenticatedClinicFeaturedPlan,
        ),
      );
    }

    // Keep linked doctors' clinicName aligned when a clinic renames itself
    if (prevName.isNotEmpty &&
        cleanName.isNotEmpty &&
        prevName.toLowerCase() != cleanName.toLowerCase()) {
      for (var i = 0; i < _allDoctors.length; i++) {
        final d = _allDoctors[i];
        if (d.clinicName.trim().toLowerCase() == prevName.toLowerCase()) {
          _allDoctors[i] = DoctorModel(
            id: d.id,
            userId: d.userId,
            name: d.name,
            specialty: d.specialty,
            qualification: d.qualification,
            experienceYears: d.experienceYears,
            rating: d.rating,
            reviewCount: d.reviewCount,
            clinicName: cleanName,
            phone: d.phone,
            email: d.email,
            status: d.status,
            verificationStatus: d.verificationStatus,
            nextAvailableSlots: d.nextAvailableSlots,
            consultationFee: d.consultationFee,
            licenseNumber: d.licenseNumber,
            photoBytes: d.photoBytes,
            clinicAddress: cleanLoc.isNotEmpty ? cleanLoc : d.clinicAddress,
            city: d.city,
            pincode: d.pincode,
            state: d.state,
            bio: d.bio,
            languages: d.languages,
            latitude: d.latitude,
            longitude: d.longitude,
            procedureFees: d.procedureFees,
          );
        }
      }
    }

    await _saveToStorage();
    notifyListeners();

    final apiRes = await _api.updateClinicProfileApi(
      clinicId: resolvedId,
      clinicName: cleanName,
      location: cleanLoc,
      coverImageUrl: coverImageUrl,
      isFeatured: isFeatured,
      featuredPlan: featuredPlan,
    );
    return {'success': true, 'clinicId': resolvedId, 'apiResult': apiRes};
  }

  Future<Map<String, dynamic>> confirmBookingByClinic(String requestId) async {
    final reqIdx = _requests.indexWhere((r) => r.id == requestId);
    final assignedIdx = _dentistAssignedRequests.indexWhere((r) => r.id == requestId);
    if (reqIdx == -1 && assignedIdx == -1) {
      return {'success': false, 'message': 'Booking not found.'};
    }

    String patientName = 'Patient';
    String patientId = '';
    String? slot;
    String? dateStr;

    if (reqIdx != -1) {
      _requests[reqIdx].status = 'Confirmed';
      patientName = _requests[reqIdx].patientName;
      patientId = _requests[reqIdx].patientId ?? '';
      slot = _requests[reqIdx].confirmedTimeSlot;
      dateStr = _requests[reqIdx].confirmedDate;
    }
    if (assignedIdx != -1) {
      _dentistAssignedRequests[assignedIdx].status = 'Confirmed';
      patientName = _dentistAssignedRequests[assignedIdx].patientName;
      patientId = _dentistAssignedRequests[assignedIdx].patientId ?? patientId;
      slot ??= _dentistAssignedRequests[assignedIdx].confirmedTimeSlot;
      dateStr ??= _dentistAssignedRequests[assignedIdx].confirmedDate;
    }

    addNotification(
      recipientRole: 'Patient',
      recipientId: patientId.isNotEmpty ? patientId : patientName,
      title: 'Appointment Confirmed',
      message: 'Your clinic booking has been confirmed.',
    );

    await _saveToStorage();
    notifyListeners();

    try {
      final res = await _api.acceptAppointment(requestId);
      if (res['success'] != true) {
        await _api.acceptProblemRequest(
          requestId: requestId,
          timeSlot: slot,
          date: dateStr,
        );
      }
    } catch (_) {}

    return {'success': true, 'message': 'Booking confirmed.'};
  }

  Future<Map<String, dynamic>> cancelBookingByClinic(
    String requestId, {
    String? reason,
  }) async {
    final reqIdx = _requests.indexWhere((r) => r.id == requestId);
    final assignedIdx = _dentistAssignedRequests.indexWhere((r) => r.id == requestId);
    if (reqIdx == -1 && assignedIdx == -1) {
      return {'success': false, 'message': 'Booking not found.'};
    }

    final cleanReason = (reason ?? '').trim();
    String patientName = 'Patient';
    String patientId = '';

    if (reqIdx != -1) {
      _requests[reqIdx].status = 'Cancelled';
      if (cleanReason.isNotEmpty) {
        _requests[reqIdx].adminNotes = 'Cancelled by clinic: $cleanReason';
      }
      patientName = _requests[reqIdx].patientName;
      patientId = _requests[reqIdx].patientId ?? '';
    }
    if (assignedIdx != -1) {
      _dentistAssignedRequests[assignedIdx].status = 'Cancelled';
      if (cleanReason.isNotEmpty) {
        _dentistAssignedRequests[assignedIdx].adminNotes = 'Cancelled by clinic: $cleanReason';
      }
      patientName = _dentistAssignedRequests[assignedIdx].patientName;
      patientId = _dentistAssignedRequests[assignedIdx].patientId ?? patientId;
    }

    addNotification(
      recipientRole: 'Patient',
      recipientId: patientId.isNotEmpty ? patientId : patientName,
      title: 'Appointment Cancelled',
      message: cleanReason.isNotEmpty
          ? 'Your clinic booking was cancelled ($cleanReason).'
          : 'Your clinic booking was cancelled.',
    );

    await _saveToStorage();
    notifyListeners();

    try {
      await _api.cancelAppointment(requestId);
    } catch (_) {}

    return {'success': true, 'message': 'Booking cancelled.'};
  }

  Future<Map<String, dynamic>> submitClinicAdRequest({
    required String clinicName,
    required String headline,
    required String targetAudience,
    String? notes,
  }) async {
    final cleanClinic = clinicName.trim().isEmpty ? 'Clinic' : clinicName.trim();
    final cleanHeadline = headline.trim();
    final cleanNotes = (notes ?? '').trim();
    final summaryMsg = cleanNotes.isNotEmpty
        ? '$cleanClinic requested a GS HEALTH sponsored banner for $targetAudience: "$cleanHeadline" ($cleanNotes).'
        : '$cleanClinic requested a GS HEALTH sponsored banner for $targetAudience: "$cleanHeadline".';

    addNotification(
      recipientRole: 'Admin',
      recipientId: 'ALL_ADMINS',
      title: 'Sponsored Banner Request',
      message: summaryMsg,
    );

    await _api.createInAppNotification(
      recipientRole: 'Admin',
      recipientId: 'ALL_ADMINS',
      title: 'Sponsored Banner Request',
      message: summaryMsg,
      type: 'CLINIC_AD_REQUEST',
    );

    return {'success': true, 'message': 'Sponsored banner request submitted.'};
  }
}


