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
  final String verificationStatus; // 'VERIFIED', 'PENDING_VERIFICATION', 'REJECTED', 'SUSPENDED'
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
    this.verificationStatus = 'VERIFIED',
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
        'verificationStatus': verificationStatus,
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
      verificationStatus: json['verification_status'] ?? json['verificationStatus'] ?? 'VERIFIED',
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
  String? confirmedTimeSlot;
  String? confirmedDate;
  String? adminNotes;
  bool whatsappNotificationSent;

  PatientConsultationRequest({
    required this.id,
    required this.patientName,
    required this.patientPhone,
    required this.problemCategory,
    required this.problemDescription,
    this.symptoms = '',
    this.preferredLocation = '',
    this.attachments = const [],
    required this.severity,
    required this.submittedAt,
    this.status = 'PENDING_ADMIN_REVIEW',
    this.assignedDoctorId,
    this.assignedDoctorName,
    this.assignedDoctorSpecialty,
    this.assignedDoctorClinic,
    this.confirmedTimeSlot,
    this.confirmedDate,
    this.adminNotes,
    this.whatsappNotificationSent = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'problemCategory': problemCategory,
        'problemDescription': problemDescription,
        'symptoms': symptoms,
        'preferredLocation': preferredLocation,
        'attachments': attachments,
        'severity': severity,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status,
        'assignedDoctorId': assignedDoctorId,
        'assignedDoctorName': assignedDoctorName,
        'assignedDoctorSpecialty': assignedDoctorSpecialty,
        'assignedDoctorClinic': assignedDoctorClinic,
        'confirmedTimeSlot': confirmedTimeSlot,
        'confirmedDate': confirmedDate,
        'adminNotes': adminNotes,
        'whatsappNotificationSent': whatsappNotificationSent,
      };

  factory PatientConsultationRequest.fromJson(Map<String, dynamic> json) {
    return PatientConsultationRequest(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      patientName: json['patientName'] ?? json['patient_name'] ?? '',
      patientPhone: json['patientPhone'] ?? json['patient_phone'] ?? '',
      problemCategory: json['problemCategory'] ?? json['problem_category'] ?? '',
      problemDescription: json['problemDescription'] ?? json['problem_description'] ?? '',
      symptoms: json['symptoms'] ?? '',
      preferredLocation: json['preferredLocation'] ?? json['preferred_location'] ?? '',
      attachments: List<String>.from(json['attachments'] ?? []),
      severity: json['severity'] ?? 'Moderate',
      submittedAt: json['submittedAt'] != null 
          ? DateTime.parse(json['submittedAt']) 
          : (json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now()),
      status: json['status'] ?? 'PENDING_ADMIN_REVIEW',
      assignedDoctorId: (json['assignedDoctorId'] ?? json['suggested_dentist_id'])?.toString(),
      assignedDoctorName: (() {
        final dName = json['assignedDoctorName'] ?? json['suggested_dentist']?['users']?['name'];
        if (dName == null || dName.toString() == 'null' || dName.toString().trim().isEmpty) return null;
        return dName.toString().trim();
      })(),
      assignedDoctorSpecialty: json['assignedDoctorSpecialty'] ?? json['suggested_dentist']?['speciality'],
      assignedDoctorClinic: json['assignedDoctorClinic'] ?? json['suggested_dentist']?['clinics']?['clinic_name'],
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

      // 5. Load Master Patients List
      final patStr = prefs.getString('dentaguru_all_patients');
      if (patStr != null && patStr.isNotEmpty) {
        final List list = jsonDecode(patStr);
        _allPatients.clear();
        _allPatients.addAll(list.map((item) => PatientProfile.fromJson(item)));
      }

      // 6. Sync live patients, appointments, clinics, doctors, records, and requests directly from Supabase DB API
      syncAllDataFromApi();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading PatientProblemService state from storage: $e');
    }
  }

  Future<void> syncAllDataFromApi() async {
    try {
      await syncPatientsFromApi();
      await syncClinicsFromApi();
      await syncDoctorsFromApi();
      await syncAppointmentsFromApi();
      await syncProblemRequestsFromApi();
      await syncMedicalRecordsFromApi();
    } catch (e) {
      debugPrint('Error in syncAllDataFromApi: $e');
    }
  }

  Future<void> syncPatientsFromApi() async {
    try {
      final list = await ApiService().fetchPatients();
      if (list.isNotEmpty) {
        _allPatients.clear();
        for (final item in list) {
          final id = (item['id'] ?? '').toString();
          String name = (item['name'] ?? '').toString().trim();
          final email = (item['email'] ?? '').toString().trim();
          final phone = (item['phone'] ?? '').toString().trim();
          final age = (item['age'] ?? '28').toString();

          if (name.isEmpty && email.isNotEmpty) {
            name = email.split('@').first;
          }
          if (name.isEmpty) {
            name = 'Patient';
          }

          _allPatients.add(PatientProfile(
            id: id,
            name: name,
            email: email,
            phone: phone,
            age: age,
          ));
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

  Future<void> syncProblemRequestsFromApi() async {
    try {
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : null;
      final List problemReqs = currentPatient.email.contains('admin')
          ? await ApiService().fetchAdminProblemRequests()
          : await ApiService().fetchPatientProblemRequests(patientId: pId);

      if (problemReqs.isNotEmpty) {
        for (final pr in problemReqs) {
          final prId = (pr['_id'] ?? pr['id'] ?? '').toString();
          if (prId.isEmpty) continue;
          final category = (pr['problem_category'] ?? pr['problemCategory'] ?? 'Dental Issue').toString();
          final desc = (pr['problem_description'] ?? pr['problemDescription'] ?? '').toString();
          final status = (pr['status'] ?? 'PENDING_ADMIN_REVIEW').toString();
          final severity = (pr['severity'] ?? 'Moderate').toString();

          final patientObj = pr['patient'] ?? {};
          final pName = (patientObj['name'] ?? pr['patientName'] ?? (currentPatient.name.isNotEmpty ? currentPatient.name : 'Patient')).toString();
          final pPhone = (patientObj['phone'] ?? pr['patientPhone'] ?? currentPatient.phone).toString();

          final existingIdx = _requests.indexWhere((r) => r.id == prId);
          if (existingIdx != -1) {
            _requests[existingIdx].status = status;
            if (pName.isNotEmpty && pName != 'Patient') _requests[existingIdx].patientName = pName;
            if (pPhone.isNotEmpty) _requests[existingIdx].patientPhone = pPhone;
            if (pr['admin_notes'] != null) _requests[existingIdx].adminNotes = pr['admin_notes'].toString();
          } else {
            _requests.insert(
              0,
              PatientConsultationRequest(
                id: prId,
                patientName: pName,
                patientPhone: pPhone,
                problemCategory: category,
                problemDescription: desc,
                severity: severity,
                submittedAt: pr['created_at'] != null ? DateTime.parse(pr['created_at']) : DateTime.now(),
                status: status,
                adminNotes: pr['admin_notes']?.toString(),
              ),
            );
          }
        }
        _saveToStorage();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync problem requests error: $e');
    }
  }

  Future<void> syncClinicsFromApi() async {
    try {
      final list = await ApiService().fetchClinics();
      if (list.isNotEmpty) {
        _allClinics.clear();
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
          final name = (userObj['name'] ?? dMap['name'] ?? 'Dentist').toString();
          final email = (userObj['email'] ?? dMap['email'] ?? '').toString();
          final phone = (userObj['phone'] ?? dMap['phone'] ?? '+1 202 555 0100').toString();
          final specialty = (dMap['speciality'] ?? dMap['specialty'] ?? 'General Dentistry').toString();
          final licNum = (dMap['license_number'] ?? dMap['licenseNumber'] ?? 'DEN-LIC-REG').toString();
          final cName = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? dMap['clinicName'] ?? '').toString();
          final cLoc = (clinicObj['location'] ?? dMap['location'] ?? 'Healthcare Hub').toString();

          final formattedName = name.startsWith('Dr.') ? name : 'Dr. $name';

          _allDoctors.add(DoctorModel(
            id: id.isNotEmpty ? id : 'DOC-${100 + _allDoctors.length + 1}',
            name: formattedName,
            specialty: specialty,
            qualification: 'BDS, MDS',
            experienceYears: 5,
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
          ));
        }
      }
      _saveToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Sync doctors error: $e');
    }
  }

  Future<void> syncAppointmentsFromApi() async {
    try {
      final pId = currentPatient.id.isNotEmpty ? currentPatient.id : null;
      final dId = currentDoctor?.id.isNotEmpty == true ? currentDoctor!.id : null;
      final list = await ApiService().fetchAppointments(patientId: pId, dentistId: dId);
      
      if (list.isNotEmpty) {
        for (final item in list) {
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
            final matchedDoc = _allDoctors.firstWhere((d) => d.id == rawD, orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''));
            if (matchedDoc.name.isNotEmpty) {
              assignedDocName = matchedDoc.name;
            }
          }

          final clinicObj = item['clinic'] ?? {};
          final clinic = (clinicObj['clinic_name'] ?? clinicObj['name'] ?? item['clinic_name'] ?? item['clinicName'] ?? '').toString();
          final treatment = item['treatment'] ?? 'Dental Consultation';
          final slot = item['time_slot'] ?? item['timeSlot'];
          final statusStr = (item['status'] ?? 'CONFIRMED').toString();

          final existingIndex = _requests.indexWhere((r) => r.id == reqId || (r.patientName == pName && r.assignedDoctorName != null && r.confirmedTimeSlot == slot?.toString()));
          if (existingIndex != -1) {
            if (pName != 'Patient Consultation') {
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
            _requests[existingIndex].status = statusStr;
            if (clinic.isNotEmpty) {
              _requests[existingIndex].assignedDoctorClinic = clinic;
            }
          } else {
            _requests.add(
              PatientConsultationRequest(
                id: reqId,
                patientName: pName,
                patientPhone: pPhone,
                problemCategory: treatment.toString(),
                problemDescription: 'Scheduled dental consultation',
                severity: 'Moderate',
                submittedAt: item['created_at'] != null ? DateTime.parse(item['created_at']) : DateTime.now(),
                status: statusStr,
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
      }

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
      if (currentDoctor != null) {
        await prefs.setString('dentaguru_current_doctor', jsonEncode(currentDoctor!.toJson()));
      }
      await prefs.setString('dentaguru_requests', jsonEncode(_requests.map((r) => r.toJson()).toList()));
      await prefs.setString('dentaguru_all_doctors', jsonEncode(_allDoctors.map((d) => d.toJson()).toList()));
      await prefs.setString('dentaguru_all_patients', jsonEncode(_allPatients.map((p) => p.toJson()).toList()));
      await prefs.setString('dentaguru_medical_records', jsonEncode(_medicalRecords));
    } catch (e) {
      debugPrint('Error saving PatientProblemService state to storage: $e');
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
    final newReq = PatientConsultationRequest(
      id: 'PR-${DateTime.now().millisecondsSinceEpoch}',
      patientName: currentPatient.name,
      patientPhone: currentPatient.phone,
      problemCategory: problemCategory,
      problemDescription: problemDescription,
      symptoms: symptoms,
      preferredLocation: preferredLocation,
      attachments: attachments,
      severity: severity,
      submittedAt: DateTime.now(),
      status: 'PENDING_ADMIN_REVIEW',
    );
    _requests.insert(0, newReq);
    _saveToStorage();
    notifyListeners();

    // 🌐 Save immediately to Supabase PostgreSQL database table ('patient_problem_requests')
    try {
      await ApiService().createProblemRequest(
        problemCategory: problemCategory,
        problemDescription: problemDescription,
        symptoms: symptoms,
        preferredLocation: preferredLocation,
        attachments: attachments,
      );
      await syncAppointmentsFromApi();
    } catch (e) {
      debugPrint('Error saving problem request to Supabase DB: $e');
    }
  }


  void assignDoctorToRequest({
    required String requestId,
    required DoctorModel doctor,
    required String adminNotes,
  }) {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      final req = _requests[index];
      req.status = 'Doctor Suggested';
      req.assignedDoctorId = doctor.id;
      req.assignedDoctorName = doctor.name;
      req.assignedDoctorSpecialty = doctor.specialty;
      req.assignedDoctorClinic = doctor.clinicName;
      req.adminNotes = adminNotes;
      req.whatsappNotificationSent = true;

      // Dispatch Notification to Dentist
      addNotification(
        recipientRole: 'Dentist',
        recipientId: doctor.id,
        title: '🩺 New Patient Referral Assigned',
        message: 'Admin suggested patient ${req.patientName} (${req.problemCategory}) to your workspace.',
      );

      _saveToStorage();
      notifyListeners();
    }
  }

  Future<void> acceptReferralByDentist(String requestId, {String? timeSlot, String? date}) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      final req = _requests[index];
      req.status = 'Confirmed';
      if (timeSlot != null && timeSlot.trim().isNotEmpty) {
        req.confirmedTimeSlot = timeSlot.trim();
      } else if (req.confirmedTimeSlot == null || req.confirmedTimeSlot!.isEmpty) {
        req.confirmedTimeSlot = 'Today, 2:30 PM';
      }
      if (date != null && date.trim().isNotEmpty) {
        req.confirmedDate = date.trim();
      }

      final slotText = req.confirmedTimeSlot ?? 'Today, 2:30 PM';

      // 1. Create & Persist Appointment in Supabase DB ('appointments' table)
      try {
        await ApiService().createAppointment(
          patientId: req.patientName,
          dentistId: req.assignedDoctorId ?? '',
          clinicId: req.assignedDoctorClinic ?? '',
          date: date ?? DateTime.now().toIso8601String(),
          timeSlot: slotText,
          treatment: req.problemCategory,
        );
        await syncAppointmentsFromApi();
      } catch (e) {
        debugPrint('Error persisting appointment in acceptReferralByDentist: $e');
      }

      // 2. Dispatch Notifications to Patient & Admin
      addNotification(
        recipientRole: 'Patient',
        recipientId: req.patientName,
        title: '🎉 Consultation Accepted!',
        message: '${req.assignedDoctorName ?? "Your Doctor"} accepted your consultation for ${req.problemCategory}. Confirmed Time Slot: $slotText',
      );

      addNotification(
        recipientRole: 'Admin',
        recipientId: 'ALL_ADMINS',
        title: '✅ Doctor Accepted Referral',
        message: '${req.assignedDoctorName ?? "Doctor"} accepted consultation for ${req.patientName}. Time Slot: $slotText',
      );

      _saveToStorage();
      notifyListeners();
    }
  }

  void declineReferralByDentist(String requestId) {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index != -1) {
      final req = _requests[index];
      final oldDocName = req.assignedDoctorName ?? 'Doctor';
      req.status = 'Pending Admin Review';
      req.assignedDoctorId = null;
      req.assignedDoctorName = null;
      req.adminNotes = 'Declined by $oldDocName. Returned to pending review pool.';

      // Dispatch Notification to Admin
      addNotification(
        recipientRole: 'Admin',
        recipientId: 'ALL_ADMINS',
        title: '⚠️ Doctor Declined Referral',
        message: '$oldDocName declined consultation for ${req.patientName}. Returned to admin pool.',
      );

      _saveToStorage();
      notifyListeners();
    }
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
    final cleanLicense = licenseNumber.trim().isEmpty ? 'DEN-LIC-${DateTime.now().millisecondsSinceEpoch}' : licenseNumber.trim();
    final cleanClinic = clinicName.trim();
    final cleanSpecialty = specialty.trim().isEmpty ? 'General Dentistry' : specialty.trim();
    final cleanAddress = clinicAddress.trim();

    final existingDoc = _allDoctors.firstWhere((d) => d.email.trim().toLowerCase() == email.trim().toLowerCase(), orElse: () => DoctorModel(id: '', name: '', specialty: '', qualification: '', experienceYears: 0, rating: 0, reviewCount: 0, clinicName: '', phone: '', email: '', status: '', nextAvailableSlots: [], consultationFee: ''));
    final doctorId = existingDoc.id.isNotEmpty ? existingDoc.id : 'DOC-${100 + _allDoctors.length + 1}';

    final newDoctor = DoctorModel(
      id: doctorId,
      name: formattedName.isEmpty ? 'Dr. New Dentist' : formattedName,
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
    );

    if (!_allDoctors.any((d) => d.email.toLowerCase() == newDoctor.email.toLowerCase())) {
      _allDoctors.insert(0, newDoctor);
    } else {
      final idx = _allDoctors.indexWhere((d) => d.email.toLowerCase() == newDoctor.email.toLowerCase());
      if (idx != -1) _allDoctors[idx] = newDoctor;
    }
    currentDoctor = newDoctor;

    if (cleanClinic.isNotEmpty && !_allClinics.any((c) => c.clinicName.toLowerCase() == cleanClinic.toLowerCase())) {
      _allClinics.insert(
        0,
        ClinicModel(
          id: 'CLN-${DateTime.now().millisecondsSinceEpoch}',
          clinicName: cleanClinic,
          location: cleanAddress,
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
      password: 'Password123!',
      phone: phone.trim().isEmpty ? '+91${DateTime.now().millisecondsSinceEpoch.toString().substring(3)}' : phone.trim(),
      role: 'Dentist',
      specialty: cleanSpecialty,
      licenseNumber: cleanLicense,
      clinicName: cleanClinic,
      clinicAddress: cleanAddress,
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
      notifyListeners();
    } catch (e) {
      debugPrint('Reset error: $e');
    }
  }
}

