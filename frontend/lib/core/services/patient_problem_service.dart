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
  });
}

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

  // Directory of All Doctors in the Platform
  final List<DoctorModel> _allDoctors = [
    DoctorModel(
      id: 'DOC-101',
      name: 'Dr. Sarah Jenkins',
      specialty: 'Orthodontics & Aligners',
      qualification: 'BDS, MDS (Orthodontics)',
      experienceYears: 12,
      rating: 4.9,
      reviewCount: 142,
      clinicName: 'Apex Dental & Aligners Center',
      phone: '+1 202 555 0199',
      email: 'dr.jenkins@dentaguru.com',
      status: 'Available',
      nextAvailableSlots: ['Today, 2:30 PM', 'Today, 4:00 PM', 'Tomorrow, 10:00 AM'],
      consultationFee: '\$75',
    ),
    DoctorModel(
      id: 'DOC-102',
      name: 'Dr. Michael Chen',
      specialty: 'Endodontics & Root Canal',
      qualification: 'BDS, MDS (Endodontics)',
      experienceYears: 15,
      rating: 4.9,
      reviewCount: 188,
      clinicName: 'Metro Root Canal Clinic',
      phone: '+1 202 555 0188',
      email: 'dr.chen@dentaguru.com',
      status: 'Available',
      nextAvailableSlots: ['Today, 3:15 PM', 'Tomorrow, 11:30 AM', 'Tomorrow, 2:00 PM'],
      consultationFee: '\$90',
    ),
    DoctorModel(
      id: 'DOC-103',
      name: 'Dr. Elena Rodriguez',
      specialty: 'Pediatric & General Dentistry',
      qualification: 'BDS, Fellow Pediatric Dentistry',
      experienceYears: 9,
      rating: 4.8,
      reviewCount: 116,
      clinicName: 'Sunshine Smiles Dental',
      phone: '+1 202 555 0177',
      email: 'dr.elena@dentaguru.com',
      status: 'Available',
      nextAvailableSlots: ['Today, 5:00 PM', 'Tomorrow, 09:00 AM'],
      consultationFee: '\$60',
    ),
    DoctorModel(
      id: 'DOC-104',
      name: 'Dr. Robert Vance',
      specialty: 'Oral & Maxillofacial Surgery',
      qualification: 'BDS, MS (Oral Surgery)',
      experienceYears: 18,
      rating: 4.95,
      reviewCount: 210,
      clinicName: 'City Surgical Dental Hospital',
      phone: '+1 202 555 0166',
      email: 'dr.vance@dentaguru.com',
      status: 'In Consultation',
      nextAvailableSlots: ['Tomorrow, 1:00 PM', 'Day After, 10:30 AM'],
      consultationFee: '\$120',
    ),
    DoctorModel(
      id: 'DOC-105',
      name: 'Dr. Ananya Sharma',
      specialty: 'Periodontics & Gum Care',
      qualification: 'BDS, MDS (Periodontology)',
      experienceYears: 8,
      rating: 4.7,
      reviewCount: 94,
      clinicName: 'Healthy Gums Laser Clinic',
      phone: '+1 202 555 0155',
      email: 'dr.sharma@dentaguru.com',
      status: 'Available',
      nextAvailableSlots: ['Today, 4:30 PM', 'Tomorrow, 3:00 PM'],
      consultationFee: '\$70',
    ),
    DoctorModel(
      id: 'DOC-106',
      name: 'Dr. Marcus Brody',
      specialty: 'Cosmetic Dentistry & Veneers',
      qualification: 'BDS, AACD Certified',
      experienceYears: 14,
      rating: 4.85,
      reviewCount: 165,
      clinicName: 'Hollywood Smile Studio',
      phone: '+1 202 555 0144',
      email: 'dr.brody@dentaguru.com',
      status: 'Available',
      nextAvailableSlots: ['Tomorrow, 11:00 AM', 'Tomorrow, 4:00 PM'],
      consultationFee: '\$100',
    ),
  ];

  List<DoctorModel> get allDoctors => List.unmodifiable(_allDoctors);

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
      assignedDoctorId: 'DOC-101',
      assignedDoctorName: 'Dr. Sarah Jenkins',
      assignedDoctorSpecialty: 'Orthodontics & Aligners',
      assignedDoctorClinic: 'Apex Dental & Aligners Center',
      adminNotes: 'Recommended Dr. Sarah Jenkins for specialized wire trimming & aligner check.',
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
  }) {
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
    );

    _allDoctors.insert(0, newDoctor);
    notifyListeners();
    return newDoctor;
  }
}

