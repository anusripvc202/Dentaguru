import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/screens/patient_details_screen.dart';
import 'package:dentaguru/features/admin/presentation/screens/sub_admin_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late List<Map<String, dynamic>> rawPatients;
  late List<Map<String, dynamic>> rawRequests;
  late List<Map<String, dynamic>> rawReferrals;
  late List<Map<String, dynamic>> rawSubAdmins;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      return null;
    });

    rawPatients = [
      {
        'id': 'pat-a-hyd',
        'name': 'Ananya Hyderabad',
        'email': 'ananya@example.com',
        'phone': '9111111111',
        'role': 'Patient',
        'state': 'Telangana',
        'district': 'Hyderabad',
        'districtId': 'dist-hyd',
        'city': 'Hyderabad',
        'pincode': '500032',
        'districtIdentificationStatus': 'IDENTIFIED',
      },
      {
        'id': 'pat-b-vja',
        'name': 'Bhaskar Vijayawada',
        'email': 'bhaskar@example.com',
        'phone': '9222222222',
        'role': 'Patient',
        'state': 'Andhra Pradesh',
        'district': 'Vijayawada',
        'districtId': 'dist-vijayawada',
        'city': 'Vijayawada',
        'pincode': '520001',
        'districtIdentificationStatus': 'IDENTIFIED',
      },
      {
        'id': 'pat-c-missing',
        'name': 'Charan Unverified',
        'email': 'charan@example.com',
        'phone': '9333333333',
        'role': 'Patient',
        'state': '',
        'district': '',
        'districtId': '',
        'city': 'Unknown Hamlet',
        'pincode': '',
        'districtIdentificationStatus': 'PENDING_ADMIN_REVIEW',
      },
    ];

    rawRequests = [
      {
        'id': 'req-a-hyd',
        'patient_id': 'pat-a-hyd',
        'patientName': 'Ananya Hyderabad',
        'patientPhone': '9111111111',
        'state': 'Telangana',
        'district': 'Hyderabad',
        'districtId': 'dist-hyd',
        'city': 'Hyderabad',
        'pincode': '500032',
        'problemCategory': 'Dental Pain',
        'problemDescription': 'Molar pain in District A',
        'status': 'SUBMITTED',
        'created_at': '2026-11-27T09:00:00Z',
      },
      {
        'id': 'req-b-vja',
        'patient_id': 'pat-b-vja',
        'patientName': 'Bhaskar Vijayawada',
        'patientPhone': '9222222222',
        'state': 'Andhra Pradesh',
        'district': 'Vijayawada',
        'districtId': 'dist-vijayawada',
        'city': 'Vijayawada',
        'pincode': '520001',
        'problemCategory': 'Checkup',
        'problemDescription': 'Checkup in District B',
        'status': 'SUBMITTED',
        'created_at': '2026-11-27T09:30:00Z',
      },
    ];

    rawReferrals = [
      {
        'id': 'ref-a-hyd',
        'referred_patient_id': 'pat-a-hyd',
        'referred_patient_name': 'Ananya Hyderabad',
        'referred_patient_mobile': '9111111111',
        'referred_patient_state': 'Telangana',
        'referred_patient_district': 'Hyderabad',
        'patient_district_id': 'dist-hyd',
        'referred_patient_city': 'Hyderabad',
        'referred_patient_pincode': '500032',
        'doctor_id': 'dent-hyd-1',
        'doctor_name': 'Dr. Sri Hyderabad',
        'clinic_id': 'clinic-hyd-1',
        'status': 'Pending',
        'created_at': '2026-11-27T10:00:00Z',
      },
      {
        'id': 'ref-b-vja',
        'referred_patient_id': 'pat-b-vja',
        'referred_patient_name': 'Bhaskar Vijayawada',
        'referred_patient_mobile': '9222222222',
        'referred_patient_state': 'Andhra Pradesh',
        'referred_patient_district': 'Vijayawada',
        'patient_district_id': 'dist-vijayawada',
        'referred_patient_city': 'Vijayawada',
        'referred_patient_pincode': '520001',
        'doctor_id': 'dent-hyd-1', // Doctor is in Hyderabad, patient is in District B!
        'doctor_name': 'Dr. Sri Hyderabad',
        'clinic_id': 'clinic-hyd-1',
        'status': 'Pending',
        'created_at': '2026-11-27T10:15:00Z',
      },
    ];

    rawSubAdmins = [
      {
        'id': 'sub-admin-1',
        'name': 'Sub Admin Hyderabad',
        'email': 'sub@gshealth.com',
        'phone': '9000000011',
        'status': 'ACTIVE',
        'permissions': ['PATIENT_VIEW', 'PROBLEM_VIEW', 'ASSIGNMENT_VIEW', 'REFERRAL_VIEW'],
        'assignedDistricts': [
          {'id': 'dist-hyd', 'name': 'Hyderabad', 'state': 'Telangana'}
        ],
      },
    ];

    ApiService.debugAdminAppointmentsOverride = () async => [];
    ApiService.debugFetchClinicsOverride = () async => [];
    ApiService.debugFetchDentistsOverride = ({
      String? city,
      String? pincode,
      String? state,
      String? specialty,
      String? language,
      List<String>? languages,
      String? search,
      String? availability,
      bool includeUnavailable = false,
    }) async =>
        [
          {
            'id': 'dent-hyd-1',
            'name': 'Dr. Sri Hyderabad',
            'speciality': 'General Medicine',
            'city': 'Hyderabad',
            'state': 'Telangana',
            'pincode': '500001',
            'availability_status': 'Available',
            'verification_status': 'VERIFIED',
          }
        ];
    ApiService.debugFetchSubAdminsOverride = () async => rawSubAdmins;
    ApiService.debugFetchPatientsOverride = ({String? search, String? state, String? districtId}) async {
      final svc = PatientProblemService();
      if (!svc.isSubAdminMode) return rawPatients;
      final allowedIds = svc.subAdminAssignedDistrictIds;
      return rawPatients.where((p) {
        final dId = (p['districtId'] ?? '').toString().toLowerCase();
        return dId.isNotEmpty && allowedIds.contains(dId);
      }).toList();
    };
    ApiService.debugFetchAdminProblemRequestsOverride = ({String? status}) async => rawRequests;
    ApiService.debugAdminReferralsOverride = () async => {
          'success': true,
          'referrals': rawReferrals,
        };

    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchClinicsOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugFetchPatientsOverride = null;
    ApiService.debugFetchAdminProblemRequestsOverride = null;
    ApiService.debugAdminReferralsOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  test('Service-level Sub-Admin district strictness blocks other districts, missing districts & referrals via doctor district', () async {
    final svc = PatientProblemService();
    svc.clearSubAdminSession();
    svc.setAdminMode(true);
    await svc.syncPatientsFromApi();
    await svc.syncProblemRequestsFromApi();
    await svc.syncAdminReferralsFromApi();

    // Main Admin mode sees all 3 patients, 2 requests, 2 referrals
    expect(svc.getPatientsForCurrentRole().length, 3);
    expect(svc.getRequestsForCurrentRole().length, 2);
    expect(svc.getReferralsForCurrentRole().length, 2);

    // Sub-Admin with 0 assigned districts sees 0 patients/requests/referrals
    svc.setSubAdminSession(
      id: 'sub-admin-empty',
      name: 'Unassigned Sub-Admin',
      email: 'none@gshealth.com',
      phone: '9000000099',
      permissions: const ['PATIENT_VIEW', 'PROBLEM_VIEW', 'REFERRAL_VIEW'],
      assignedDistricts: const [],
    );
    expect(svc.getPatientsForCurrentRole(), isEmpty);
    expect(svc.getRequestsForCurrentRole(), isEmpty);
    expect(svc.getReferralsForCurrentRole(), isEmpty);

    // Assign District A (dist-hyd) to Sub-Admin A
    svc.setSubAdminSession(
      id: 'sub-admin-1',
      name: 'Sub Admin Hyderabad',
      email: 'sub@gshealth.com',
      phone: '9000000011',
      permissions: const ['PATIENT_VIEW', 'PROBLEM_VIEW', 'REFERRAL_VIEW'],
      assignedDistricts: const [
        {'id': 'dist-hyd', 'name': 'Hyderabad', 'state': 'Telangana'}
      ],
    );

    final visiblePatients = svc.getPatientsForCurrentRole();
    expect(visiblePatients.length, 1);
    expect(visiblePatients.first.id, 'pat-a-hyd');
    expect(visiblePatients.any((p) => p.id == 'pat-b-vja'), isFalse);
    expect(visiblePatients.any((p) => p.id == 'pat-c-missing'), isFalse);

    final visibleReqs = svc.getRequestsForCurrentRole();
    expect(visibleReqs.length, 1);
    expect(visibleReqs.first.id, 'req-a-hyd');

    final visibleRefs = svc.getReferralsForCurrentRole();
    expect(visibleRefs.length, 1);
    expect(visibleRefs.first.id, 'ref-a-hyd');
  });

  testWidgets('Sub-Admin Dashboard shows only District A patients & hides District B search results and patient details', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final svc = PatientProblemService();
    svc.setSubAdminSession(
      id: 'sub-admin-1',
      name: 'Sub Admin Hyderabad',
      email: 'sub@gshealth.com',
      phone: '9000000011',
      permissions: const ['PATIENT_VIEW', 'PROBLEM_VIEW', 'ASSIGNMENT_VIEW', 'REFERRAL_VIEW'],
      assignedDistricts: const [
        {'id': 'dist-hyd', 'name': 'Hyderabad', 'state': 'Telangana'}
      ],
    );
    await svc.syncPatientsFromApi();
    await svc.syncProblemRequestsFromApi();
    await svc.syncAdminReferralsFromApi();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SubAdminDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Overview counts reflect only District A (1 patient, 1 waiting request)
    final patStatVal = find.byKey(const Key('admin_stat_value_patients'));
    expect(patStatVal, findsOneWidget);
    expect((tester.widget<Text>(patStatVal)).data, '1');

    // Switch to Patients tab via StatCard or BottomNavigationBar
    await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Patients'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ananya Hyderabad'), findsOneWidget);
    expect(find.text('Bhaskar Vijayawada'), findsNothing);
    expect(find.text('Charan Unverified'), findsNothing);

    // Search for District B patient returns 0 results
    await tester.enterText(
      find.byKey(const Key('sub_admin_patients_search_field')),
      'Bhaskar',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Bhaskar Vijayawada'), findsNothing);
    expect(find.text('No patients in your assigned district match your search.'), findsOneWidget);

    // Direct navigation to District B patient details is blocked
    final districtBPatient = PatientProfile.fromJson(rawPatients[1]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: PatientDetailsScreen(patient: districtBPatient)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('patient_details_district_denied')), findsOneWidget);
  });

  testWidgets('Main Admin accesses all districts and filters Patients by State and District', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final svc = PatientProblemService();
    svc.clearSubAdminSession();
    svc.setAdminMode(true);
    await svc.syncPatientsFromApi();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AdminDashboardScreen(initialTab: 3)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // All 3 patients visible initially for Main Admin
    expect(find.text('Ananya Hyderabad'), findsOneWidget);
    expect(find.text('Bhaskar Vijayawada'), findsOneWidget);
    expect(find.text('Charan Unverified'), findsOneWidget);

    // Filter by State: Andhra Pradesh
    await tester.tap(find.byKey(const Key('admin_patients_state_filter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Andhra Pradesh').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Bhaskar Vijayawada'), findsOneWidget);
    expect(find.text('Ananya Hyderabad'), findsNothing);
    expect(find.text('Charan Unverified'), findsNothing);
  });
}
