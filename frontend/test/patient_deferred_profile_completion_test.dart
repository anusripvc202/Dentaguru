import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/patient_profile_requirements.dart';
import 'package:dentaguru/core/routes/app_router.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/patient/presentation/screens/ai_triage_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_profile_completion_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/talk_to_dentist_now_screen.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

final Uint8List _validTestPngBytes = Uint8List.fromList(const [
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

void _installDefaultNoNetworkOverrides() {
  ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
  ApiService.debugAdminAppointmentsOverride = () async => [];
  ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async => [];
  ApiService.debugFetchDoctorLanguagesOverride = ({bool includeUnavailable = false}) async => ['English', 'Hindi'];
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
  ApiService.debugFetchClinicReferralsOverride = ({String? clinicId, String? clinicName}) async => [];
  ApiService.debugFetchConversationsOverride = () async => [];
}

void _clearAllOverrides() {
  ApiService.debugRequestOtpOverride = null;
  ApiService.debugVerifyOtpOverride = null;
  ApiService.debugLoginOverride = null;
  ApiService.debugUpdatePatientProfileOverride = null;
  ApiService.debugFetchAppointmentsOverride = null;
  ApiService.debugAdminAppointmentsOverride = null;
  ApiService.debugFetchNotificationsOverride = null;
  ApiService.debugFetchDoctorLanguagesOverride = null;
  ApiService.debugFetchDentistsOverride = null;
  ApiService.debugFetchClinicsOverride = null;
  ApiService.debugFetchDoctorReferralsOverride = null;
  ApiService.debugFetchClinicReferralsOverride = null;
  ApiService.debugFetchConversationsOverride = null;
  PatientProfileCompletionScreen.debugPickImageOverride = null;
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 4, int ms = 250}) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    _installDefaultNoNetworkOverrides();
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
    appRouter.go('/login');
  });

  tearDown(() async {
    _clearAllOverrides();
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  group('DentaGuru Patient Login & Deferred Profile Completion (Scenarios 1-6)', () {
    testWidgets(
      'Scenario 1: New patient logs in with OTP and lands directly on Patient Dashboard without forced profile completion',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async => {
          'success': true,
          'message': 'Verification code ready on screen (testing mode).',
          'otp': '654321',
          'deliveryMode': 'on_screen',
          'isAdmin': false,
        };
        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async => {
          'success': code == '654321',
          'isNewPatient': true,
          'accessToken': 'pat-jwt-new-1',
          'refreshToken': 'pat-refresh-new-1',
          'user': {
            'id': 'pat-new-6001',
            'name': 'Patient',
            'phone': '9123456001',
            'email': 'user_9123456001@dentaguru.internal',
            'role': 'Patient',
            'age': '',
            'gender': '',
            'pincode': '',
            'profilePhoto': null,
            'isProfileComplete': false,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              routerConfig: appRouter,
            ),
          ),
        );
        await _pumpFrames(tester);

        expect(find.text('Sign in with mobile'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).first, '9123456001');
        await tester.tap(find.text('Send code'));
        await _pumpFrames(tester);

        expect(find.text('Enter your code'), findsOneWidget);
        final otpFields = find.byType(TextFormField);
        expect(otpFields, findsNWidgets(6));
        const digits = ['6', '5', '4', '3', '2', '1'];
        for (int i = 0; i < 6; i++) {
          await tester.enterText(otpFields.at(i), digits[i]);
          await tester.pump();
        }
        await _pumpFrames(tester);

        final verifyBtn = find.widgetWithText(ElevatedButton, 'Verify & continue');
        if (verifyBtn.evaluate().isNotEmpty) {
          await tester.ensureVisible(verifyBtn);
          await tester.tap(verifyBtn);
          await _pumpFrames(tester);
        }

        // Lands directly on PatientDashboardScreen; Profile Completion is deferred
        expect(find.byType(PatientDashboardScreen), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);
        expect(PatientProblemService().currentPatient.id, equals('pat-new-6001'));
        expect(PatientProblemService().currentPatient.isProfileComplete, isFalse);
      },
    );

    testWidgets(
      'Scenario 2: Clicking any service with incomplete profile redirects to Profile Completion and validates required fields (with optional profile image)',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-incomplete-201',
          name: 'Patient',
          phone: '9123456002',
          age: '',
          gender: '',
          pincode: '',
          photoBytes: null,
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        // 1. Tapping AI Triage opens Profile Completion instead of AiTriageScreen
        await tester.tap(find.byKey(const Key('patient_ai_triage_card')));
        await _pumpFrames(tester);
        expect(find.byType(PatientProfileCompletionScreen), findsOneWidget);
        expect(find.byType(AiTriageScreen), findsNothing);

        // Empty submit fails mandatory checks (pincode, age, gender); profile image is optional by default
        final submitBtn = find.byKey(const Key('profile_completion_submit_button'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await _pumpFrames(tester);
        expect(find.text('Profile image is required.'), findsNothing);
        expect(find.text('Pincode is required'), findsOneWidget);
        expect(find.text('Age is required'), findsOneWidget);
        expect(find.text('Please select your gender.'), findsOneWidget);

        // Invalid pincode (<6 digits) & age (>120) also rejected
        await tester.enterText(find.byKey(const Key('profile_completion_pincode_field')), '500');
        await tester.enterText(find.byKey(const Key('profile_completion_age_field')), '150');
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await _pumpFrames(tester);
        expect(find.text('Please enter a valid 6-digit pincode'), findsOneWidget);
        expect(find.text('Please enter a valid age (1-120)'), findsOneWidget);

        // Back button returns to Dashboard without opening service
        await tester.tap(find.byKey(const Key('profile_completion_back_button')));
        await _pumpFrames(tester);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);
        expect(find.byType(AiTriageScreen), findsNothing);

        // 2. Bottom nav tabs (Find / Visits / Locker) also trigger Profile Completion
        for (final tabLabel in ['Find', 'Visits', 'Locker']) {
          final tab = find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.text(tabLabel),
          );
          await tester.tap(tab);
          await _pumpFrames(tester);
          expect(find.byType(PatientProfileCompletionScreen), findsOneWidget, reason: '$tabLabel must require profile completion');
          await tester.tap(find.byKey(const Key('profile_completion_back_button')));
          await _pumpFrames(tester);
        }

        // 3. Talk to a Dentist card also triggers Profile Completion
        final talkCard = find.byKey(const Key('talk_to_dentist_now_card'));
        await tester.ensureVisible(talkCard);
        await tester.tap(talkCard);
        await _pumpFrames(tester);
        expect(find.byType(PatientProfileCompletionScreen), findsOneWidget);
        expect(find.byType(TalkToDentistNowScreen), findsNothing);
      },
    );

    testWidgets(
      'Scenario 3: Completing profile saves against existing Patient ID and opens originally selected service automatically',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const existingUserId = 'pat-existing-deferred-301';
        await SessionService().saveSession(
          token: 'pat-jwt-301',
          role: 'Patient',
          userId: existingUserId,
          phone: '9123456003',
          name: 'Patient',
        );
        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: existingUserId,
          name: 'Patient',
          phone: '9123456003',
          age: '',
          gender: '',
          pincode: '',
        );

        String? updatedPatientId;
        String? updatedPincode;
        String? updatedAge;
        String? updatedGender;
        String? updatedPhoto;
        bool? updatedCompleteFlag;
        int updateCalls = 0;

        ApiService.debugUpdatePatientProfileOverride = ({
          required String patientId,
          String? pincode,
          String? age,
          String? gender,
          String? profilePhoto,
          String? name,
          String? city,
          bool completeProfile = true,
        }) async {
          updateCalls++;
          updatedPatientId = patientId;
          updatedPincode = pincode;
          updatedAge = age;
          updatedGender = gender;
          updatedPhoto = profilePhoto;
          updatedCompleteFlag = completeProfile;
          return {
            'success': true,
            'user': {
              'id': patientId,
              'name': name ?? 'Meera Nair',
              'pincode': pincode,
              'age': age,
              'gender': gender,
              'profilePhoto': profilePhoto,
              'isProfileComplete': true,
            },
          };
        };

        PatientProfileCompletionScreen.debugPickImageOverride = () async => _validTestPngBytes;

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        // Patient selects AI Triage -> sent to Profile Completion first
        await tester.tap(find.byKey(const Key('patient_ai_triage_card')));
        await _pumpFrames(tester);
        expect(find.byType(PatientProfileCompletionScreen), findsOneWidget);

        // Fill mandatory fields: Image, Pincode, Age, Gender (+ optional Name)
        await tester.tap(find.byKey(const Key('profile_completion_upload_photo_button')));
        await _pumpFrames(tester);
        await tester.enterText(find.byKey(const Key('profile_completion_name_field')), 'Meera Nair');
        await tester.enterText(find.byKey(const Key('profile_completion_pincode_field')), '500081');
        await tester.enterText(find.byKey(const Key('profile_completion_age_field')), '28');
        final genderFemale = find.byKey(const Key('profile_completion_gender_Female'));
        await tester.ensureVisible(genderFemale);
        await tester.tap(genderFemale);
        await _pumpFrames(tester);

        final submitBtn = find.byKey(const Key('profile_completion_submit_button'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await _pumpFrames(tester, count: 6, ms: 250);

        // Verifies in-place save against exact existing user ID (no duplicate)
        expect(updateCalls, equals(1));
        expect(updatedPatientId, equals(existingUserId));
        expect(updatedPincode, equals('500081'));
        expect(updatedAge, equals('28'));
        expect(updatedGender, equals('Female'));
        expect(updatedCompleteFlag, isTrue);
        expect(updatedPhoto, equals('data:image/png;base64,${base64Encode(_validTestPngBytes)}'));
        expect(service.currentPatient.id, equals(existingUserId));
        expect(service.currentPatient.isProfileComplete, isTrue);

        // Automatically continued to originally selected service: AiTriageScreen
        expect(find.byType(AiTriageScreen), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);
      },
    );

    testWidgets(
      'Scenario 4: Existing patient with complete profile opens services directly without Profile Completion page',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-complete-401',
          name: 'Arjun Rao',
          phone: '9123456004',
          age: '32',
          gender: 'Male',
          pincode: '500033',
          photoBytes: _validTestPngBytes,
        );
        expect(service.currentPatient.isProfileComplete, isTrue);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        // 1. Find tab -> FindDoctorsScreen directly
        await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Find')));
        await _pumpFrames(tester);
        expect(find.byType(FindDoctorsScreen), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);
        await tester.tap(find.byKey(const Key('back_to_patient_dashboard_button')));
        await _pumpFrames(tester);

        // 2. Visits & Locker tabs open directly
        await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Visits')));
        await _pumpFrames(tester);
        expect(find.text('My visits'), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);

        await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Locker')));
        await _pumpFrames(tester);
        expect(find.text('Your medical & health records'), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);

        // 3. Home -> Hero Book a Visit opens dialog directly without Profile Completion
        await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Home')));
        await _pumpFrames(tester);
        final heroBanner = find.text('No upcoming visits');
        await tester.ensureVisible(heroBanner);
        await tester.tap(heroBanner);
        await _pumpFrames(tester);
        expect(find.byType(BookVisitFlowDialog), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);
      },
    );

    testWidgets(
      'Scenario 5: Closing and reopening app before completion requests Profile Completion again; after completion opens services directly',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const restartUserId = 'pat-restart-501';
        await SessionService().saveSession(
          token: 'pat-jwt-501',
          role: 'Patient',
          userId: restartUserId,
          phone: '9123456005',
          name: 'Patient',
          metadata: const {
            'age': '',
            'gender': '',
            'pincode': '',
            'isProfileComplete': false,
          },
        );

        // Simulate closing app before completing profile and cold-launching from '/'
        SessionService().resetInMemoryCacheForTest();
        await PatientProblemService().clearPatientSessionCache();
        appRouter.go('/');

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              routerConfig: appRouter,
            ),
          ),
        );
        await _pumpFrames(tester, count: 6, ms: 250);

        expect(find.byType(PatientDashboardScreen), findsOneWidget);
        expect(PatientProblemService().currentPatient.isProfileComplete, isFalse);

        // Next service attempt asks for Profile Completion
        await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Find')));
        await _pumpFrames(tester);
        expect(find.byType(PatientProfileCompletionScreen), findsOneWidget);

        // Complete profile now
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
          'user': {
            'id': patientId,
            'pincode': pincode,
            'age': age,
            'gender': gender,
            'profilePhoto': profilePhoto,
            'isProfileComplete': true,
          },
        };
        PatientProfileCompletionScreen.debugPickImageOverride = () async => _validTestPngBytes;

        await tester.tap(find.byKey(const Key('profile_completion_upload_photo_button')));
        await _pumpFrames(tester);
        await tester.enterText(find.byKey(const Key('profile_completion_pincode_field')), '500081');
        await tester.enterText(find.byKey(const Key('profile_completion_age_field')), '26');
        final femaleBtn = find.byKey(const Key('profile_completion_gender_Female'));
        await tester.ensureVisible(femaleBtn);
        await tester.tap(femaleBtn);
        await _pumpFrames(tester);
        final submitBtn = find.byKey(const Key('profile_completion_submit_button'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await _pumpFrames(tester, count: 5, ms: 250);
        expect(find.byType(FindDoctorsScreen), findsOneWidget);

        // Now close & reopen app AFTER completing profile -> service opens directly
        SessionService().resetInMemoryCacheForTest();
        await PatientProblemService().clearPatientSessionCache();
        appRouter.go('/');
        await _pumpFrames(tester, count: 6, ms: 250);

        expect(find.byType(PatientDashboardScreen), findsOneWidget);
        expect(PatientProblemService().currentPatient.isProfileComplete, isTrue);

        await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Find')));
        await _pumpFrames(tester);
        expect(find.byType(FindDoctorsScreen), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);
      },
    );

    testWidgets(
      'Scenario 6: Doctor & Clinic OTP login and unregistered flows remain unchanged, and Profile Completion has zero narrow-viewport overflow',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async => {
          'success': true,
          'otp': '112233',
          'deliveryMode': 'on_screen',
          'isAdmin': false,
        };

        // 6A. Existing Doctor login -> /dentist directly
        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async => {
          'success': true,
          'accessToken': 'doc-jwt-601',
          'user': {
            'id': 'doc-usr-601',
            'dentistId': 'doc-601',
            'userId': 'doc-usr-601',
            'name': 'Rohan Gupta',
            'phone': '9123456010',
            'email': 'rohan@gshealth.in',
            'role': 'Dentist',
            'specialty': 'Cardiology',
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              routerConfig: appRouter,
            ),
          ),
        );
        await _pumpFrames(tester);

        await tester.tap(find.byKey(const Key('signin_role_dentist')));
        await _pumpFrames(tester);
        await tester.enterText(find.byType(TextFormField).first, '9123456010');
        await tester.tap(find.text('Send code'));
        await _pumpFrames(tester);

        final docOtpFields = find.byType(TextFormField);
        const otpDigits = ['1', '1', '2', '2', '3', '3'];
        for (int i = 0; i < 6; i++) {
          await tester.enterText(docOtpFields.at(i), otpDigits[i]);
          await tester.pump();
        }
        await _pumpFrames(tester);
        final verifyDocBtn = find.widgetWithText(ElevatedButton, 'Verify & continue');
        if (verifyDocBtn.evaluate().isNotEmpty) {
          await tester.ensureVisible(verifyDocBtn);
          await tester.tap(verifyDocBtn);
          await _pumpFrames(tester);
        }
        expect(find.byType(DentistTimelineScreen), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);

        // Reset session -> 6B. Existing Clinic login -> /clinic directly
        await SessionService().clearSession();
        await PatientProblemService().clearAllData();
        appRouter.go('/login');
        await _pumpFrames(tester);

        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async => {
          'success': true,
          'accessToken': 'clinic-jwt-602',
          'user': {
            'id': 'clinic-usr-602',
            'clinicId': 'clinic-602',
            'clinicName': 'Sunshine Dental Studio',
            'name': 'Sunshine Dental Studio',
            'phone': '9123456011',
            'email': 'clinic@gshealth.in',
            'role': 'Clinic',
          },
        };

        await tester.tap(find.byKey(const Key('signin_role_clinic')));
        await _pumpFrames(tester);
        await tester.enterText(find.byType(TextFormField).first, '9123456011');
        await tester.tap(find.text('Send code'));
        await _pumpFrames(tester);

        final clinicOtpFields = find.byType(TextFormField);
        for (int i = 0; i < 6; i++) {
          await tester.enterText(clinicOtpFields.at(i), otpDigits[i]);
          await tester.pump();
        }
        await _pumpFrames(tester);
        final verifyClinicBtn = find.widgetWithText(ElevatedButton, 'Verify & continue');
        if (verifyClinicBtn.evaluate().isNotEmpty) {
          await tester.ensureVisible(verifyClinicBtn);
          await tester.tap(verifyClinicBtn);
          await _pumpFrames(tester);
        }
        expect(find.byType(ClinicDashboardScreen), findsOneWidget);
        expect(find.byType(PatientProfileCompletionScreen), findsNothing);

        // Reset session -> 6C. Unregistered Clinic OTP transitions to Registration (never PatientDashboard)
        await SessionService().clearSession();
        await PatientProblemService().clearAllData();
        appRouter.go('/login');
        await _pumpFrames(tester);

        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async => {
          'success': true,
          'verified': true,
        };
        ApiService.debugLoginOverride = ({String? email, String? otp, String? password, String? phone, String? role}) async => {
          'success': false,
          'message': 'Invalid credentials. User not registered in system.',
        };

        await tester.tap(find.byKey(const Key('signin_role_clinic')));
        await _pumpFrames(tester);
        await tester.enterText(find.byType(TextFormField).first, '9123456012');
        await tester.tap(find.text('Send code'));
        await _pumpFrames(tester);
        final unregClinicFields = find.byType(TextFormField);
        for (int i = 0; i < 6; i++) {
          await tester.enterText(unregClinicFields.at(i), otpDigits[i]);
          await tester.pump();
        }
        await _pumpFrames(tester);
        final verifyUnregBtn = find.widgetWithText(ElevatedButton, 'Verify & continue');
        if (verifyUnregBtn.evaluate().isNotEmpty) {
          await tester.ensureVisible(verifyUnregBtn);
          await tester.tap(verifyUnregBtn);
          await _pumpFrames(tester);
        }
        expect(find.text('Welcome to\nGS HEALTH'), findsOneWidget);
        expect(find.byType(PatientDashboardScreen), findsNothing);

        // 6D. Narrow mobile viewport responsiveness on PatientProfileCompletionScreen (320, 360, 390, 412)
        for (final width in [320.0, 360.0, 390.0, 412.0]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                key: ValueKey('pc_viewport_$width'),
                debugShowCheckedModeBanner: false,
                home: const PatientProfileCompletionScreen(serviceTitle: 'AI Health Triage'),
              ),
            ),
          );
          await _pumpFrames(tester, count: 2, ms: 200);
          expect(tester.takeException(), isNull, reason: 'PatientProfileCompletionScreen overflowed at ${width}px');
        }
      },
    );

    testWidgets(
      'Scenario 7: Profile image is optional by default, completion succeeds without image, and existing photo is preserved on update',
      (tester) async {
        expect(PatientProfileRequirementsConfig.requireProfileImage, isFalse);

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const patientId = 'pat-optional-photo-701';
        await SessionService().saveSession(
          token: 'pat-jwt-701',
          role: 'Patient',
          userId: patientId,
          phone: '9123456077',
          name: 'Patient',
        );

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: patientId,
          name: 'Patient',
          phone: '9123456077',
          age: '',
          gender: '',
          pincode: '',
          photoBytes: null,
        );

        String? capturedPhoto;
        ApiService.debugUpdatePatientProfileOverride = ({
          required String patientId,
          String? pincode,
          String? age,
          String? gender,
          String? profilePhoto,
          String? name,
          String? city,
          bool completeProfile = true,
        }) async {
          capturedPhoto = profilePhoto;
          return {
            'success': true,
            'user': {
              'id': patientId,
              'name': name ?? 'Kavya Sharma',
              'pincode': pincode,
              'age': age,
              'gender': gender,
              'profilePhoto': profilePhoto,
              'isProfileComplete': true,
            },
          };
        };

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await _pumpFrames(tester);

        await tester.tap(find.byKey(const Key('patient_ai_triage_card')));
        await _pumpFrames(tester);
        expect(find.byType(PatientProfileCompletionScreen), findsOneWidget);

        // Fill only pincode, age, gender (no photo uploaded)
        await tester.enterText(find.byKey(const Key('profile_completion_pincode_field')), '500081');
        await tester.enterText(find.byKey(const Key('profile_completion_age_field')), '29');
        final femaleBtn = find.byKey(const Key('profile_completion_gender_Female'));
        await tester.ensureVisible(femaleBtn);
        await tester.tap(femaleBtn);
        await _pumpFrames(tester);

        final submitBtn = find.byKey(const Key('profile_completion_submit_button'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await _pumpFrames(tester, count: 5, ms: 200);

        expect(capturedPhoto, isNull);
        expect(service.currentPatient.isProfileComplete, isTrue);
        expect(find.byType(AiTriageScreen), findsOneWidget);

        // Existing photo is preserved when profile fields are updated without a new image
        service.updatePatientProfile(
          id: patientId,
          name: 'Kavya Sharma',
          email: '',
          phone: '9123456077',
          age: '29',
          gender: 'Female',
          bloodGroup: 'O+',
          emergencyContact: '9123456077',
          address: 'Banjara Hills',
          city: 'Hyderabad',
          pincode: '500081',
          photoBytes: _validTestPngBytes,
          preserveExistingPhoto: true,
          syncRemote: false,
        );
        expect(service.currentPatient.photoBytes, equals(_validTestPngBytes));

        service.updatePatientProfile(
          id: patientId,
          name: 'Kavya Sharma',
          email: '',
          phone: '9123456077',
          age: '30',
          gender: 'Female',
          bloodGroup: 'O+',
          emergencyContact: '9123456077',
          address: 'Banjara Hills',
          city: 'Hyderabad',
          pincode: '500081',
          photoBytes: null,
          profileImageUrl: null,
          preserveExistingPhoto: true,
          syncRemote: false,
        );
        expect(service.currentPatient.photoBytes, equals(_validTestPngBytes));
      },
    );
  });
}
