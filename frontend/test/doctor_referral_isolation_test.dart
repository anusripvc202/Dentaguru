import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      (call) async => null,
    );
  });

  const sharedClinicId = '11111111-aaaa-4111-8111-111111111111';
  const sharedClinicName = 'Devi Multi-Specialty Clinic';

  const docAId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const docAUserId = 'aaaaaaaa-9999-4111-8111-aaaaaaaaaaaa';
  const docBId = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  const docBUserId = 'bbbbbbbb-9999-4222-8222-bbbbbbbbbbbb';
  const docCId = 'cccccccc-3333-4333-8333-cccccccccccc';
  const docCUserId = 'cccccccc-9999-4333-8333-cccccccccccc';

  final docA = DoctorModel(
    id: docAId,
    userId: docAUserId,
    name: 'Dr. Rohitha',
    specialty: 'Dermatology',
    qualification: 'MBBS, MD',
    experienceYears: 6,
    rating: 4.9,
    reviewCount: 20,
    clinicName: sharedClinicName,
    phone: '9876500011',
    email: 'rohitha@devi.test',
    status: 'Available',
    nextAvailableSlots: const ['10:00 AM'],
    consultationFee: '₹600',
  );

  final docB = DoctorModel(
    id: docBId,
    userId: docBUserId,
    name: 'Dr. Arjun',
    specialty: 'Cardiology',
    qualification: 'MBBS, DM',
    experienceYears: 9,
    rating: 4.8,
    reviewCount: 30,
    clinicName: sharedClinicName,
    phone: '9876500012',
    email: 'arjun@devi.test',
    status: 'Available',
    nextAvailableSlots: const ['11:00 AM'],
    consultationFee: '₹800',
  );

  final docC = DoctorModel(
    id: docCId,
    userId: docCUserId,
    name: 'Dr. Kiran',
    specialty: 'Orthopedics',
    qualification: 'MBBS, MS',
    experienceYears: 7,
    rating: 4.7,
    reviewCount: 15,
    clinicName: sharedClinicName,
    phone: '9876500013',
    email: 'kiran@devi.test',
    status: 'Available',
    nextAvailableSlots: const ['02:00 PM'],
    consultationFee: '₹700',
  );

  late List<Map<String, dynamic>> serverReferrals;
  late List<Map<String, dynamic>> serverNotifications;
  late PatientProblemService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = PatientProblemService();
    await service.clearAllDataAndStorage();

    serverReferrals = [
      {
        'id': 'ref-docA-satya',
        'referrerPatientId': 'pat-anu-1',
        'referrerPatientName': 'Anu',
        'referredPatientId': 'pat-satya-1',
        'referredPatientName': 'Satya',
        'referredPatientMobile': '9063663179',
        'requiredSpecialist': 'Dermatology',
        'clinicalComplaint': 'Skin rash consultation with Dr. Rohitha',
        'doctorId': docAId,
        'clinicId': sharedClinicId,
        'doctorName': 'Dr. Rohitha',
        'doctorSpecialty': 'Dermatology',
        'doctorClinicName': sharedClinicName,
        'status': 'Pending',
      },
      {
        'id': 'ref-docB-ramesh',
        'referrerPatientId': 'pat-anu-1',
        'referrerPatientName': 'Anu',
        'referredPatientId': 'pat-ramesh-1',
        'referredPatientName': 'Ramesh',
        'referredPatientMobile': '9063663188',
        'requiredSpecialist': 'Cardiology',
        'clinicalComplaint': 'ECG review with Dr. Arjun',
        'doctorId': docBId,
        'clinicId': sharedClinicId,
        'doctorName': 'Dr. Arjun',
        'doctorSpecialty': 'Cardiology',
        'doctorClinicName': sharedClinicName,
        'status': 'Pending',
      },
    ];

    serverNotifications = [
      {
        'id': 'notif-docA-1',
        'recipient_role': 'Dentist',
        'recipient_id': docAUserId,
        'title': 'New Patient Referral',
        'message': 'Anu referred Satya to you.',
        'type': 'NEW_REFERRAL',
        'referral_id': 'ref-docA-satya',
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'id': 'notif-docB-1',
        'recipient_role': 'Dentist',
        'recipient_id': docBUserId,
        'title': 'New Patient Referral',
        'message': 'Anu referred Ramesh to you.',
        'type': 'NEW_REFERRAL',
        'referral_id': 'ref-docB-ramesh',
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      },
    ];

    ApiService.debugFetchClinicAppointmentsOverride = ({String? clinicId, String? clinicName}) async => [];
    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    ApiService.debugAdminAppointmentsOverride = () async => [];

    // Backend-enforced strict filtering per doctorId (docA, docB, docC)
    ApiService.debugFetchDoctorReferralsOverride = ({String? doctorId}) async {
      final d = (doctorId ?? '').trim();
      return serverReferrals.where((r) {
        final rDoc = (r['doctorId'] ?? '').toString();
        if (d == docAId || d == docAUserId) return rDoc == docAId || rDoc == docAUserId;
        if (d == docBId || d == docBUserId) return rDoc == docBId || rDoc == docBUserId;
        if (d == docCId || d == docCUserId) return rDoc == docCId || rDoc == docCUserId;
        return false;
      }).toList();
    };

    ApiService.debugFetchClinicReferralsOverride = ({String? clinicId, String? clinicName}) async {
      return serverReferrals.where((r) => r['clinicId'] == sharedClinicId).toList();
    };

    // Even if admin referrals pool were somehow populated, doctor view MUST NOT leak clinic referrals!
    ApiService.debugAdminReferralsOverride = () async => {
      'success': true,
      'referrals': serverReferrals,
    };

    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async {
      final normRole = (role ?? '').trim().toLowerCase();
      final uid = (userId ?? '').trim();
      return serverNotifications.where((n) {
        final nr = (n['recipient_role'] ?? '').toString().toLowerCase();
        final nid = (n['recipient_id'] ?? '').toString();
        if (normRole == 'dentist') {
          if (uid == docAId || uid == docAUserId) return nr == 'dentist' && (nid == docAId || nid == docAUserId);
          if (uid == docBId || uid == docBUserId) return nr == 'dentist' && (nid == docBId || nid == docBUserId);
          if (uid == docCId || uid == docCUserId) return nr == 'dentist' && (nid == docCId || nid == docCUserId);
        }
        return false;
      }).toList();
    };
  });

  tearDown(() async {
    ApiService.debugFetchClinicAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchDoctorReferralsOverride = null;
    ApiService.debugFetchClinicReferralsOverride = null;
    ApiService.debugAdminReferralsOverride = null;
    ApiService.debugFetchNotificationsOverride = null;
    await SessionService().clearSession();
    await service.clearAllDataAndStorage();
  });

  Future<void> signInAsDoctor(DoctorModel doc) async {
    await SessionService().clearSession();
    await service.clearAllData();
    service.addTestDoctor(docA);
    service.addTestDoctor(docB);
    service.addTestDoctor(docC);
    service.currentDoctor = doc;
    service.setDentistMode(true);
    await SessionService().saveSession(
      token: 'tok_${doc.id}',
      role: 'Dentist',
      userId: doc.userId,
      email: doc.email,
      phone: doc.phone,
      name: doc.name,
      metadata: {
        'dentistId': doc.id,
        'userId': doc.userId,
        'clinicId': sharedClinicId,
        'clinicName': doc.clinicName,
      },
    );
  }

  testWidgets('Test A, B & E: Logout & Login across 3 doctors in same clinic strictly isolates Incoming Referrals & Notifications', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 1. Doctor A (Dr. Rohitha) logs in -> sees ONLY Satya (and NOT Ramesh)
    await signInAsDoctor(docA);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: DentistTimelineScreen())));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Incoming Patient Referrals (1)'), findsWidgets);
    expect(find.textContaining('Satya'), findsWidgets);
    expect(find.textContaining('Ramesh'), findsNothing);
    expect(
      service.getNotificationsForRole('Dentist').map((n) => n.message),
      allOf(contains('Anu referred Satya to you.'), isNot(contains('Anu referred Ramesh to you.'))),
    );
    expect(tester.takeException(), isNull);

    // Unmount and Logout -> Doctor B (Dr. Arjun, same clinic!) logs in -> sees ONLY Ramesh (and NOT Satya!)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await signInAsDoctor(docB);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: DentistTimelineScreen())));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Incoming Patient Referrals (1)'), findsWidgets);
    expect(find.textContaining('Ramesh'), findsWidgets);
    expect(find.textContaining('Satya'), findsNothing);
    expect(
      service.getNotificationsForRole('Dentist').map((n) => n.message),
      allOf(contains('Anu referred Ramesh to you.'), isNot(contains('Anu referred Satya to you.'))),
    );
    expect(tester.takeException(), isNull);

    // Unmount and Logout -> Doctor C (Dr. Kiran, same clinic!) logs in -> sees 0 Incoming Patient Referrals!
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await signInAsDoctor(docC);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: DentistTimelineScreen())));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('doctor_today_incoming_referrals_section')), findsNothing);
    expect(find.textContaining('Satya'), findsNothing);
    expect(find.textContaining('Ramesh'), findsNothing);
    expect(service.doctorReceivedPatientReferrals, isEmpty);
    expect(service.getNotificationsForRole('Dentist'), isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Security Regression: Even if adminPatientReferrals pool has same-clinic referrals, Doctor C sees ZERO foreign referrals', (tester) async {
    await signInAsDoctor(docC);
    // Simulate legacy leak vector by directly seeding adminPatientReferrals
    service.addTestAdminPatientReferral(
      PatientReferral(
        id: 'ref-leak-1',
        referrerPatientId: 'pat-anu-1',
        referrerPatientName: 'Anu',
        referredPatientName: 'Satya',
        referredPatientMobile: '9063663179',
        requiredSpecialist: 'Dermatology',
        clinicalComplaint: 'Skin rash',
        doctorId: docAId,
        doctorName: 'Dr. Rohitha',
        doctorClinicName: sharedClinicName,
        status: 'Pending',
      ),
    );

    await service.syncDoctorReferralsFromApi();
    expect(service.doctorReceivedPatientReferrals, isEmpty);
  });

  testWidgets('Test C: Authorized Clinic Dashboard displays clinic referrals across its doctors with intended doctor names', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await SessionService().saveSession(
      token: 'tok_clinic',
      role: 'Clinic',
      userId: sharedClinicId,
      email: 'admin@devi.test',
      phone: '9876500001',
      name: sharedClinicName,
      metadata: {'clinicId': sharedClinicId, 'clinicName': sharedClinicName},
    );
    service.setAuthenticatedClinicSession(
      id: sharedClinicId,
      clinicName: sharedClinicName,
      location: 'Kompally, Hyderabad',
    );
    service.addTestDoctor(docA);
    service.addTestDoctor(docB);
    service.addTestDoctor(docC);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: ClinicDashboardScreen(clinicName: sharedClinicName))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final refBtn = find.byKey(const Key('clinic_patient_referrals_card'));
    await tester.ensureVisible(refBtn);
    await tester.tap(refBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Satya'), findsWidgets);
    expect(find.textContaining('Dr. Rohitha'), findsWidgets);
    expect(find.textContaining('Ramesh'), findsWidgets);
    expect(find.textContaining('Dr. Arjun'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
