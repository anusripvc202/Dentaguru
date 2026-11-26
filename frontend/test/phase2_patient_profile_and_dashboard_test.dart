import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/patient_profile_requirements.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_profile_completion_screen.dart';

final Uint8List _testPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void _installMocks() {
  ApiService.debugFetchAppointmentsOverride =
      ({String? patientId, String? dentistId}) async => [];
  ApiService.debugAdminAppointmentsOverride = () async => [];
  ApiService.debugFetchNotificationsOverride =
      ({String? role, String? userId}) async => [];
  ApiService.debugFetchDoctorLanguagesOverride =
      ({bool includeUnavailable = false}) async => ['English', 'Hindi', 'Telugu'];
  ApiService.debugFetchDentistsOverride = ({
    String? state,
    String? city,
    String? pincode,
    String? specialty,
    String? availability,
    String? language,
    List<String>? languages,
    String? search,
    bool includeUnavailable = false,
  }) async => [];
  ApiService.debugFetchClinicsOverride = () async => [];
  ApiService.debugFetchDoctorReferralsOverride = ({String? doctorId}) async => [];
  ApiService.debugFetchClinicReferralsOverride =
      ({String? clinicId, String? clinicName}) async => [];
  ApiService.debugFetchConversationsOverride = () async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PatientProfileRequirementsConfig.resetDefaults();
    _installMocks();
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    PatientProfileRequirementsConfig.resetDefaults();
    ApiService.debugUpdatePatientProfileOverride = null;
    PatientProfileCompletionScreen.debugPickImageOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  group('Phase 2: 9-Field Configurable Profile & Real-Data Patient Dashboard', () {
    testWidgets(
      '1. Renders all 9 profile fields (with read-only verified mobile), respects configurable mandatory flags, and does not default blood group to O+',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await SessionService().saveSession(
          token: 'tok-p2-1',
          role: 'Patient',
          userId: 'pat-p2-1',
          phone: '9063663180',
          name: 'Patient',
        );
        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-p2-1',
          name: 'Patient',
          phone: '9063663180',
        );

        // Unset blood group must be empty, never silently 'O Positive (O+)'
        expect(service.currentPatient.bloodGroup, isEmpty);

        // Enable flexible mandatory Full Name & Blood Group flags dynamically
        PatientProfileRequirementsConfig.requireFullName = true;
        PatientProfileRequirementsConfig.requireBloodGroup = true;
        expect(service.currentPatient.isProfileComplete, isFalse);
        expect(
          service.currentPatient.missingRequiredProfileFields,
          containsAll(['Full name', 'Blood group']),
        );

        ApiService.debugUpdatePatientProfileOverride = ({
          required String patientId,
          String? pincode,
          String? age,
          String? gender,
          String? profilePhoto,
          String? name,
          String? city,
          bool completeProfile = true,
        }) async => {
          'success': true,
          'user': {'id': patientId, 'name': name},
        };
        PatientProfileCompletionScreen.debugPickImageOverride =
            () async => _testPng;

        bool completedCalled = false;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: PatientProfileCompletionScreen(
                serviceTitle: 'Book Consultation',
                onCompleted: () => completedCalled = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify all 9 sections/fields exist and mobile is read-only + Verified
        expect(find.byKey(const Key('profile_completion_image_section')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_name_field')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_mobile_readonly')), findsOneWidget);
        expect(find.text('+91 9063663180'), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_pincode_field')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_age_field')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_gender_section')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_address_field')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_languages_section')), findsOneWidget);
        expect(find.byKey(const Key('profile_completion_blood_group_section')), findsOneWidget);

        // Fill all fields including multi-language & blood group
        await tester.tap(find.byKey(const Key('profile_completion_upload_photo_button')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('profile_completion_name_field')), 'Kavya Reddy');
        await tester.enterText(find.byKey(const Key('profile_completion_pincode_field')), '500081');
        await tester.enterText(find.byKey(const Key('profile_completion_age_field')), '31');
        await tester.tap(find.byKey(const Key('profile_completion_gender_Female')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('profile_completion_address_field')),
          'Plot 42, Madhapur',
        );

        final teluguChip = find.byKey(const Key('profile_completion_lang_Telugu'));
        await tester.ensureVisible(teluguChip);
        await tester.tap(teluguChip);
        await tester.pump();

        final bgChip = find.byKey(const Key('profile_completion_blood_B+'));
        await tester.ensureVisible(bgChip);
        await tester.tap(bgChip);
        await tester.pump();

        final submitBtn = find.byKey(const Key('profile_completion_submit_button'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(completedCalled, isTrue);
        expect(service.currentPatient.name, equals('Kavya Reddy'));
        expect(service.currentPatient.address, equals('Plot 42, Madhapur'));
        expect(service.currentPatient.bloodGroup, equals('B+'));
        expect(service.currentPatient.languages, containsAll(['English', 'Telugu']));
        expect(service.currentPatient.isProfileComplete, isTrue);
      },
    );

    testWidgets(
      '2. Patient Dashboard Upcoming Consultation Card shows Online/In-Person badge, Join Consultation CTA, real doctor fee (never hardcoded ₹500), and Prescriptions/Diagnostics/Previous Visits cards',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-dash-2',
          name: 'Rohit Verma',
          phone: '9888877776',
          age: '34',
          gender: 'Male',
          pincode: '500032',
          photoBytes: _testPng,
        );

        service.addTestDoctor(
          DoctorModel(
            id: 'doc-cardio-1',
            name: 'Dr. Vivek Menon',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM',
            experienceYears: 12,
            rating: 0.0,
            reviewCount: 0,
            clinicName: 'Heart Care Center',
            phone: '9111122222',
            email: 'vivek@heartcare.in',
            status: 'Available',
            nextAvailableSlots: const ['11:00 AM'],
            consultationFee: '₹800',
            photoBytes: _testPng,
          ),
        );
        ApiService.debugFetchDentistsOverride = ({
          String? state,
          String? city,
          String? pincode,
          String? specialty,
          String? availability,
          String? language,
          List<String>? languages,
          String? search,
          bool includeUnavailable = false,
        }) async => [
          {
            'id': 'doc-cardio-1',
            'name': 'Dr. Vivek Menon',
            'specialty': 'Cardiology',
            'qualification': 'MBBS, MD, DM',
            'experience_years': 12,
            'rating': 0.0,
            'reviews_count': 0,
            'clinicName': 'Heart Care Center',
            'phone': '9111122222',
            'email': 'vivek@heartcare.in',
            'availability_status': 'Available',
            'consultation_fee': '₹800',
          },
        ];

        service.addTestRequest(
          PatientConsultationRequest(
            id: 'req-online-1',
            patientId: 'pat-dash-2',
            patientName: 'Rohit Verma',
            patientPhone: '9888877776',
            problemCategory: 'Online Cardiology Consultation',
            problemDescription: 'Online follow-up for blood pressure',
            symptoms: 'Online video consultation',
            severity: 'Moderate',
            submittedAt: DateTime.now(),
            status: 'CONFIRMED',
            assignedDoctorId: 'doc-cardio-1',
            assignedDoctorName: 'Dr. Vivek Menon',
            assignedDoctorSpecialty: 'Cardiology',
            assignedDoctorClinic: 'Heart Care Center',
            confirmedDate: '2027-01-15',
            confirmedTimeSlot: '11:00 AM',
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        // Home shows compact hero summary + Open Visits CTA, NOT full Upcoming Consultation cards
        expect(find.byKey(const Key('hero_appointment_title')), findsOneWidget);
        expect(find.byKey(const Key('home_open_visits_button')), findsOneWidget);
        expect(find.byKey(const Key('upcoming_consultation_card_req-online-1')), findsNothing);

        // Scroll down to health overview cards on compact Home
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const Key('dashboard_prescriptions_quick_card')), findsOneWidget);
        expect(find.byKey(const Key('dashboard_diagnostics_quick_card')), findsOneWidget);
        expect(find.byKey(const Key('dashboard_previous_visits_card')), findsOneWidget);

        // Open Visits tab to inspect full consultation card, real fee, and Join/Chat action
        await tester.tap(
          find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.text('Visits'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const Key('visit_card_req-online-1')), findsOneWidget);
        expect(find.text('ONLINE'), findsOneWidget);
        expect(find.textContaining('Fee: ₹800'), findsOneWidget);
        expect(find.textContaining('Fee: ₹500'), findsNothing);
        expect(find.byKey(const Key('chat_visit_button_req-online-1')), findsOneWidget);
        expect(find.byKey(const Key('details_visit_button_req-online-1')), findsOneWidget);
        expect(find.byKey(const Key('reschedule_visit_button_req-online-1')), findsOneWidget);
      },
    );
  });
}
