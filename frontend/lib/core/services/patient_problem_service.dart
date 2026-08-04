import 'dart:typed_data';
import 'package:flutter/material.dart';

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
}

/// Central state service for logged in patient, consultation requests, and doctor directory
class PatientProblemService extends ChangeNotifier {
  static final PatientProblemService _instance = PatientProblemService._internal();
  factory PatientProblemService() => _instance;
  PatientProblemService._internal();

  // Current Logged-in Patient Profile
  PatientProfile currentPatient = PatientProfile();

  // In-memory cache for user profile photos across sessions
  final Map<String, Uint8List> _userPhotoCache = {};

  // Current Logged-in Doctor Profile
  DoctorModel? currentDoctor;

  // Directory of All Doctors in the Platform (Loaded live from user registrations)
  final List<DoctorModel> _allDoctors = [];

  List<DoctorModel> get allDoctors => List.unmodifiable(_allDoctors);

  // List of Consultation Requests (Loaded live from user submissions)
  final List<PatientConsultationRequest> _requests = [];

  List<PatientConsultationRequest> get requests => List.unmodifiable(_requests);

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
    notifyListeners();
    return newDoctor;
  }
}

