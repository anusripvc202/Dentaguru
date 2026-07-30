import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Model representing logged-in patient profile details
class PatientProfile {
  String name;
  String email;
  String phone;
  String age;
  String gender;
  String bloodGroup;
  String emergencyContact;
  Uint8List? photoBytes;

  PatientProfile({
    this.name = 'Sarah Jenkins',
    this.email = 'sarah.jenkins@dentaguru.com',
    this.phone = '+1 202 555 0142',
    this.age = '28',
    this.gender = 'Female',
    this.bloodGroup = 'O Positive (O+)',
    this.emergencyContact = '+1 202 555 9988',
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
  String? assignedDoctorName;
  String? assignedDoctorSpecialty;
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
    this.assignedDoctorName,
    this.assignedDoctorSpecialty,
    this.adminNotes,
    this.whatsappNotificationSent = false,
  });
}

/// Central state service for logged in patient and consultation requests
class PatientProblemService extends ChangeNotifier {
  static final PatientProblemService _instance = PatientProblemService._internal();
  factory PatientProblemService() => _instance;
  PatientProblemService._internal();

  // Current Logged-in Patient Profile
  PatientProfile currentPatient = PatientProfile();

  // List of Consultation Requests
  final List<PatientConsultationRequest> _requests = [
    PatientConsultationRequest(
      id: 'PR-901',
      patientName: 'Sarah Jenkins',
      patientPhone: '+1 202 555 0142',
      problemCategory: 'Toothache & Cold Sensitivity',
      problemDescription: 'Experiencing sharp pain in lower right molar when drinking cold liquids.',
      severity: 'Severe',
      submittedAt: DateTime.now().subtract(const Duration(hours: 3)),
      status: 'Pending Admin Review',
    ),
    PatientConsultationRequest(
      id: 'PR-902',
      patientName: 'Jane Smith',
      patientPhone: '+1 202 555 0132',
      problemCategory: 'Aligners / Wire Adjustment',
      problemDescription: 'Orthodontic wire poking inside cheek causing irritation.',
      severity: 'Mild',
      submittedAt: DateTime.now().subtract(const Duration(hours: 18)),
      status: 'Doctor Suggested',
      assignedDoctorName: 'Dr. Sarah Jenkins',
      assignedDoctorSpecialty: 'Orthodontics',
      whatsappNotificationSent: true,
    ),
  ];

  List<PatientConsultationRequest> get requests => List.unmodifiable(_requests);

  void updatePatientProfile({
    required String name,
    required String email,
    required String phone,
    required String age,
    required String gender,
    required String bloodGroup,
    required String emergencyContact,
    Uint8List? photoBytes,
  }) {
    currentPatient = PatientProfile(
      name: name.trim().isEmpty ? 'Sarah Jenkins' : name.trim(),
      email: email.trim().isEmpty ? 'sarah.jenkins@dentaguru.com' : email.trim(),
      phone: phone.trim().isEmpty ? '+1 202 555 0142' : phone.trim(),
      age: age.trim().isEmpty ? '28' : age.trim(),
      gender: gender.isEmpty ? 'Female' : gender,
      bloodGroup: bloodGroup.isEmpty ? 'O Positive (O+)' : bloodGroup,
      emergencyContact: emergencyContact.trim().isEmpty ? '+1 202 555 9988' : emergencyContact.trim(),
      photoBytes: photoBytes,
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
    required String doctorName,
    required String specialty,
    required String adminNotes,
  }) {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      _requests[index].status = 'Doctor Suggested';
      _requests[index].assignedDoctorName = doctorName;
      _requests[index].assignedDoctorSpecialty = specialty;
      _requests[index].adminNotes = adminNotes;
      _requests[index].whatsappNotificationSent = true;
      notifyListeners();
    }
  }
}
