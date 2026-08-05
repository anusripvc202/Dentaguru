import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

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
  final Map<String, String> procedureFees;

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
      procedureFees: pFees.isNotEmpty ? pFees : null,
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

  // List of Issued Medical Records / Prescriptions
  final List<Map<String, dynamic>> _medicalRecords = [];

  List<Map<String, dynamic>> get medicalRecords => List.unmodifiable(_medicalRecords);

  void addMedicalRecord(Map<String, dynamic> record) {
    _medicalRecords.insert(0, record);
    _saveToStorage();
    notifyListeners();
  }

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

      // 4. Load Medical Records
      final medStr = prefs.getString('dentaguru_medical_records');
      if (medStr != null && medStr.isNotEmpty) {
        final List list = jsonDecode(medStr);
        _medicalRecords.clear();
        _medicalRecords.addAll(List<Map<String, dynamic>>.from(list));
      }

      // 5. Sync live appointments from Supabase DB API
      syncAppointmentsFromApi();

      // 4. Load All Doctors Directory
      final docListStr = prefs.getString('dentaguru_all_doctors');
      if (docListStr != null && docListStr.isNotEmpty) {
        final List dList = jsonDecode(docListStr);
        _allDoctors.clear();
        _allDoctors.addAll(dList.map((item) => DoctorModel.fromJson(item)));
      }

      if (_allDoctors.isEmpty) {
        _seedDefaultDoctors();
      }

      syncDoctorsFromApi();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading PatientProblemService state from storage: $e');
    }
  }

  void _seedDefaultDoctors() {
    _allDoctors.addAll([
      DoctorModel(
        id: 'DOC-101',
        name: 'Dr. Sarah Jenkins',
        specialty: 'Orthodontics & Braces',
        qualification: 'BDS, MDS (Orthodontics)',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 42,
        clinicName: 'Apex Dental Care & Orthodontics',
        phone: '+1 202 555 0142',
        email: 'sarah.jenkins@dentaguru.com',
        status: 'Available',
        nextAvailableSlots: ['Today, 2:30 PM', 'Tomorrow, 10:00 AM'],
        consultationFee: '\$85',
        licenseNumber: 'DEN-LIC-88401',
        clinicAddress: '450 Healthcare Blvd, Suite 201',
      ),
      DoctorModel(
        id: 'DOC-102',
        name: 'Dr. Michael Chang',
        specialty: 'Endodontics & Root Canal',
        qualification: 'BDS, MDS (Endodontics)',
        experienceYears: 12,
        rating: 4.85,
        reviewCount: 58,
        clinicName: 'Smile Dental Clinic',
        phone: '+1 202 555 0198',
        email: 'michael.chang@dentaguru.com',
        status: 'Available',
        nextAvailableSlots: ['Today, 4:00 PM', 'Tomorrow, 11:30 AM'],
        consultationFee: '\$90',
        licenseNumber: 'DEN-LIC-88402',
        clinicAddress: '782 Medical Center Drive, Suite 104',
      ),
      DoctorModel(
        id: 'DOC-103',
        name: 'Dr. Elena Rostova',
        specialty: 'General Dentistry & Preventive Care',
        qualification: 'BDS',
        experienceYears: 6,
        rating: 5.0,
        reviewCount: 31,
        clinicName: 'City Center Dental Hub',
        phone: '+1 202 555 0165',
        email: 'elena.rostova@dentaguru.com',
        status: 'Available',
        nextAvailableSlots: ['Today, 3:00 PM', 'Tomorrow, 9:00 AM'],
        consultationFee: '\$75',
        licenseNumber: 'DEN-LIC-88403',
        clinicAddress: '123 Healthcare Blvd, Medical Hub, Suite 400',
      ),
      DoctorModel(
        id: 'DOC-104',
        name: 'Dr. Marcus Vance',
        specialty: 'Oral & Maxillofacial Surgery',
        qualification: 'BDS, MDS (Oral Surgery)',
        experienceYears: 15,
        rating: 4.95,
        reviewCount: 76,
        clinicName: 'Metro Oral Surgery Center',
        phone: '+1 202 555 0111',
        email: 'marcus.vance@dentaguru.com',
        status: 'In Consultation',
        nextAvailableSlots: ['Tomorrow, 2:00 PM', 'Day after, 10:00 AM'],
        consultationFee: '\$120',
        licenseNumber: 'DEN-LIC-88404',
        clinicAddress: '900 Surgical Pavilion, Suite 500',
      ),
      DoctorModel(
        id: 'DOC-105',
        name: 'Dr. Priya Sharma',
        specialty: 'Periodontics & Gum Care',
        qualification: 'BDS, MDS (Periodontics)',
        experienceYears: 9,
        rating: 4.75,
        reviewCount: 29,
        clinicName: 'Care Dental Studio',
        phone: '+1 202 555 0177',
        email: 'priya.sharma@dentaguru.com',
        status: 'Available',
        nextAvailableSlots: ['Today, 5:00 PM', 'Tomorrow, 1:00 PM'],
        consultationFee: '\$80',
        licenseNumber: 'DEN-LIC-88405',
        clinicAddress: '310 Wellness Way, Suite 102',
      ),
    ]);
    _saveToStorage();
  }

  Future<void> syncDoctorsFromApi() async {
    try {
      final apiDentists = await ApiService().fetchDentists();
      if (apiDentists.isNotEmpty) {
        bool addedAny = false;
        for (final dMap in apiDentists) {
          final id = dMap['id']?.toString() ?? dMap['_id']?.toString() ?? '';
          final userObj = dMap['users'] ?? dMap['user'] ?? {};
          final name = (userObj['name'] ?? dMap['name'] ?? 'Dentist').toString();
          final email = (userObj['email'] ?? dMap['email'] ?? '').toString();
          final phone = (userObj['phone'] ?? dMap['phone'] ?? '+1 202 555 0100').toString();
          final specialty = (dMap['speciality'] ?? dMap['specialty'] ?? 'General Dentistry').toString();
          final licNum = (dMap['license_number'] ?? dMap['licenseNumber'] ?? 'DEN-LIC-REG').toString();
          
          final formattedName = name.startsWith('Dr.') ? name : 'Dr. $name';

          if (!_allDoctors.any((doc) => doc.id == id || (email.isNotEmpty && doc.email.toLowerCase() == email.toLowerCase()))) {
            _allDoctors.insert(0, DoctorModel(
              id: id.isNotEmpty ? id : 'DOC-${100 + _allDoctors.length + 1}',
              name: formattedName,
              specialty: specialty,
              qualification: 'BDS, MDS',
              experienceYears: 5,
              rating: (dMap['rating'] ?? 5.0).toDouble(),
              reviewCount: dMap['reviews_count'] ?? 1,
              clinicName: 'DentaGuru Registered Clinic',
              phone: phone,
              email: email,
              status: dMap['availability_status'] ?? 'Available',
              nextAvailableSlots: ['Today, 2:00 PM', 'Tomorrow, 10:00 AM'],
              consultationFee: '\$75',
              licenseNumber: licNum,
            ));
            addedAny = true;
          }
        }
        if (addedAny) {
          _saveToStorage();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Sync doctors error: $e');
    }
  }

  Future<void> syncAppointmentsFromApi() async {
    try {
      final list = await ApiService().fetchAppointments();
      if (list.isNotEmpty) {
        bool addedAny = false;
        for (final item in list) {
          final reqId = item['_id'] ?? item['id'] ?? 'REQ-${item['patient_id']}-${DateTime.now().millisecondsSinceEpoch}';
          final pName = item['patient_id'] ?? 'Patient';
          final docName = item['dentist_id'] ?? 'Assigned Specialist';
          final clinic = item['clinic_id'] ?? 'DentaGuru Care Center';
          final treatment = item['treatment'] ?? 'Dental Consultation';

          if (!_requests.any((r) => r.id == reqId || (r.patientName == pName && r.problemCategory == treatment))) {
            _requests.insert(
              0,
              PatientConsultationRequest(
                id: reqId.toString(),
                patientName: pName.toString(),
                patientPhone: '+12025550199',
                problemCategory: treatment.toString(),
                symptomDescription: 'Scheduled consultation via DentaGuru DB',
                status: 'Doctor Suggested',
                assignedDoctorName: docName.toString(),
                assignedDoctorSpecialty: 'Dental Specialist',
                assignedDoctorClinic: clinic.toString(),
                adminNotes: 'Restored from Supabase database record',
                whatsappNotificationSent: true,
              ),
            );
            addedAny = true;
          }
        }

        if (addedAny) {
          _saveToStorage();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Sync appointments error: $e');
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
      await prefs.setString('dentaguru_medical_records', jsonEncode(_medicalRecords));
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
      _seedDefaultDoctors();
      notifyListeners();
    } catch (e) {
      debugPrint('Reset error: $e');
    }
  }
}

