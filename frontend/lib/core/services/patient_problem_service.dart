import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Model representing a Doctor/Dentist registered in DentaGuru platform
class DoctorModel {
  final String id;
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
  final List<String> nextAvailableSlots;
  final String consultationFee;
  final String licenseNumber;
  final Uint8List? photoBytes;
  final String clinicAddress;

  DoctorModel({
    required this.id,
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
    required this.nextAvailableSlots,
    required this.consultationFee,
    this.licenseNumber = 'DEN-LIC-REG',
    this.photoBytes,
    this.clinicAddress = '123 Healthcare Blvd, Medical Hub, Suite 400',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
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
        'nextAvailableSlots': nextAvailableSlots,
        'consultationFee': consultationFee,
        'licenseNumber': licenseNumber,
        'clinicAddress': clinicAddress,
        'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
      };

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    Uint8List? bytes;
    if (json['photoBase64'] != null && json['photoBase64'].toString().isNotEmpty) {
      try {
        bytes = base64Decode(json['photoBase64']);
      } catch (_) {}
    }
    return DoctorModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      specialty: json['specialty'] ?? '',
      qualification: json['qualification'] ?? 'BDS, MDS',
      experienceYears: json['experienceYears'] ?? 5,
      rating: (json['rating'] ?? 5.0).toDouble(),
      reviewCount: json['reviewCount'] ?? 0,
      clinicName: json['clinicName'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      status: json['status'] ?? 'Available',
      nextAvailableSlots: List<String>.from(json['nextAvailableSlots'] ?? []),
      consultationFee: json['consultationFee'] ?? '\$75',
      licenseNumber: json['licenseNumber'] ?? 'DEN-LIC-REG',
      photoBytes: bytes,
      clinicAddress: json['clinicAddress'] ?? '123 Healthcare Blvd, Medical Hub, Suite 400',
    );
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
  Uint8List? photoBytes;

  PatientProfile({
    this.id = '',
    this.name = '',
    this.email = '',
    this.phone = '',
    this.age = '28',
    this.gender = 'Female',
    this.bloodGroup = 'O Positive (O+)',
    this.emergencyContact = '',
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
        'photoBase64': photoBytes != null ? base64Encode(photoBytes!) : null,
      };

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    Uint8List? bytes;
    if (json['photoBase64'] != null && json['photoBase64'].toString().isNotEmpty) {
      try {
        bytes = base64Decode(json['photoBase64']);
      } catch (_) {}
    }
    return PatientProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      age: json['age'] ?? '28',
      gender: json['gender'] ?? 'Female',
      bloodGroup: json['bloodGroup'] ?? 'O Positive (O+)',
      emergencyContact: json['emergencyContact'] ?? '',
      photoBytes: bytes,
    );
  }
}

/// Model representing a dental problem submitted by a patient for admin review
class PatientConsultationRequest {
  final String id;
  final String patientName;
  final String patientPhone;
  final String problemCategory;
  final String problemDescription;
  final String severity; // 'Mild', 'Moderate', 'Severe'
  final DateTime submittedAt;
  String status; // 'Pending Admin Review', 'Doctor Suggested', 'Confirmed'
  String? assignedDoctorId;
  String? assignedDoctorName;
  String? assignedDoctorSpecialty;
  String? assignedDoctorClinic;
  String? adminNotes;
  bool whatsappNotificationSent;

  PatientConsultationRequest({
    required this.id,
    required this.patientName,
    required this.patientPhone,
    required this.problemCategory,
    required this.problemDescription,
    required this.severity,
    required this.submittedAt,
    this.status = 'Pending Admin Review',
    this.assignedDoctorId,
    this.assignedDoctorName,
    this.assignedDoctorSpecialty,
    this.assignedDoctorClinic,
    this.adminNotes,
    this.whatsappNotificationSent = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'problemCategory': problemCategory,
        'problemDescription': problemDescription,
        'severity': severity,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status,
        'assignedDoctorId': assignedDoctorId,
        'assignedDoctorName': assignedDoctorName,
        'assignedDoctorSpecialty': assignedDoctorSpecialty,
        'assignedDoctorClinic': assignedDoctorClinic,
        'adminNotes': adminNotes,
        'whatsappNotificationSent': whatsappNotificationSent,
      };

  factory PatientConsultationRequest.fromJson(Map<String, dynamic> json) {
    return PatientConsultationRequest(
      id: json['id'] ?? '',
      patientName: json['patientName'] ?? '',
      patientPhone: json['patientPhone'] ?? '',
      problemCategory: json['problemCategory'] ?? '',
      problemDescription: json['problemDescription'] ?? '',
      severity: json['severity'] ?? 'Moderate',
      submittedAt: json['submittedAt'] != null ? DateTime.parse(json['submittedAt']) : DateTime.now(),
      status: json['status'] ?? 'Pending Admin Review',
      assignedDoctorId: json['assignedDoctorId'],
      assignedDoctorName: json['assignedDoctorName'],
      assignedDoctorSpecialty: json['assignedDoctorSpecialty'],
      assignedDoctorClinic: json['assignedDoctorClinic'],
      adminNotes: json['adminNotes'],
      whatsappNotificationSent: json['whatsappNotificationSent'] ?? false,
    );
  }
}

/// Central state service for logged in patient, consultation requests, and doctor directory
class PatientProblemService extends ChangeNotifier {
  static final PatientProblemService _instance = PatientProblemService._internal();
  factory PatientProblemService() => _instance;

  PatientProblemService._internal() {
    _loadFromStorage();
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

  // List of Consultation Requests
  final List<PatientConsultationRequest> _requests = [];

  List<PatientConsultationRequest> get requests => List.unmodifiable(_requests);

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

      // 2. Load Doctor Profile
      final dStr = prefs.getString('dentaguru_current_doctor');
      if (dStr != null && dStr.isNotEmpty) {
        currentDoctor = DoctorModel.fromJson(jsonDecode(dStr));
      }

      // 3. Load Consultation Requests
      final reqStr = prefs.getString('dentaguru_requests');
      if (reqStr != null && reqStr.isNotEmpty) {
        final List list = jsonDecode(reqStr);
        _requests.clear();
        _requests.addAll(list.map((item) => PatientConsultationRequest.fromJson(item)));
      }

      // 4. Load All Doctors Directory
      final docListStr = prefs.getString('dentaguru_all_doctors');
      if (docListStr != null && docListStr.isNotEmpty) {
        final List dList = jsonDecode(docListStr);
        _allDoctors.clear();
        _allDoctors.addAll(dList.map((item) => DoctorModel.fromJson(item)));
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading PatientProblemService state from storage: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dentaguru_patient_profile', jsonEncode(currentPatient.toJson()));
      if (currentDoctor != null) {
        await prefs.setString('dentaguru_current_doctor', jsonEncode(currentDoctor!.toJson()));
      }
      await prefs.setString('dentaguru_requests', jsonEncode(_requests.map((r) => r.toJson()).toList()));
      await prefs.setString('dentaguru_all_doctors', jsonEncode(_allDoctors.map((d) => d.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving PatientProblemService state to storage: $e');
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
      age: age.trim().isEmpty ? '28' : age.trim(),
      gender: gender.isEmpty ? 'Female' : gender,
      bloodGroup: bloodGroup.isEmpty ? 'O Positive (O+)' : bloodGroup,
      emergencyContact: emergencyContact.trim().isEmpty ? phone.trim() : emergencyContact.trim(),
      photoBytes: cachedPhoto,
    );
    _saveToStorage();
    notifyListeners();
  }

  void submitProblem({
    required String problemCategory,
    required String problemDescription,
    required String severity,
  }) {
    final newReq = PatientConsultationRequest(
      id: 'PR-${900 + _requests.length + 1}',
      patientName: currentPatient.name,
      patientPhone: currentPatient.phone,
      problemCategory: problemCategory,
      problemDescription: problemDescription,
      severity: severity,
      submittedAt: DateTime.now(),
      status: 'Pending Admin Review',
    );
    _requests.insert(0, newReq);
    _saveToStorage();
    notifyListeners();
  }

  void assignDoctorToRequest({
    required String requestId,
    required DoctorModel doctor,
    required String adminNotes,
  }) {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      _requests[index].status = 'Doctor Suggested';
      _requests[index].assignedDoctorId = doctor.id;
      _requests[index].assignedDoctorName = doctor.name;
      _requests[index].assignedDoctorSpecialty = doctor.specialty;
      _requests[index].assignedDoctorClinic = doctor.clinicName;
      _requests[index].adminNotes = adminNotes;
      _requests[index].whatsappNotificationSent = true;
      _saveToStorage();
      notifyListeners();
    }
  }

  DoctorModel registerDoctor({
    required String name,
    required String email,
    required String phone,
    required String licenseNumber,
    required String specialty,
    required String clinicName,
    required int experienceYears,
    String qualification = 'BDS, MDS',
    String consultationFee = '\$75',
    Uint8List? photoBytes,
    String clinicAddress = '123 Healthcare Blvd, Medical Hub, Suite 400',
  }) {
    if (photoBytes != null) {
      _userPhotoCache[email.trim().toLowerCase()] = photoBytes;
    }
    final cachedPhoto = photoBytes ?? _userPhotoCache[email.trim().toLowerCase()];

    final formattedName = name.trim().startsWith('Dr.') ? name.trim() : 'Dr. ${name.trim()}';
    final newDoctor = DoctorModel(
      id: 'DOC-${100 + _allDoctors.length + 1}',
      name: formattedName.isEmpty ? 'Dr. New Dentist' : formattedName,
      specialty: specialty.trim().isEmpty ? 'General Dentistry' : specialty.trim(),
      qualification: qualification.trim().isEmpty ? 'BDS, MDS' : qualification.trim(),
      experienceYears: experienceYears <= 0 ? 5 : experienceYears,
      rating: 5.0,
      reviewCount: 1,
      clinicName: clinicName.trim().isEmpty ? 'DentaGuru Care Center' : clinicName.trim(),
      phone: phone.trim().isEmpty ? '+1 202 555 0100' : phone.trim(),
      email: email.trim().isEmpty ? 'doctor@dentaguru.com' : email.trim(),
      status: 'Available',
      nextAvailableSlots: ['Today, 2:00 PM', 'Tomorrow, 10:00 AM'],
      consultationFee: consultationFee.trim().isEmpty ? '\$75' : consultationFee.trim(),
      licenseNumber: licenseNumber.trim().isEmpty ? 'DEN-REG-AUTO' : licenseNumber.trim(),
      photoBytes: cachedPhoto,
      clinicAddress: clinicAddress.trim().isEmpty ? '123 Healthcare Blvd, Medical Hub, Suite 400' : clinicAddress.trim(),
    );

    _allDoctors.insert(0, newDoctor);
    currentDoctor = newDoctor;
    _saveToStorage();
    notifyListeners();
    return newDoctor;
  }
}

