import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/ai_triage_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/talk_to_dentist_now_screen.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async => [];
    ApiService.debugFetchDoctorLanguagesOverride = ({bool includeUnavailable = false}) async => ['English'];
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
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    await PatientProblemService().clearAllData();
  });

  group('Phase 5: Coordinator Escalation & Floating Book a Consultation Button', () {
    testWidgets(
      '1. TalkToDentistNowScreen checks specialty online availability, never fakes connection when offline, and escalates to Coordinator',
      (tester) async {
        tester.view.physicalSize = const Size(430, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-esc-1',
          name: 'Meera Nair',
          phone: '9000088888',
          city: 'Hyderabad',
          pincode: '500081',
        );
        // Only a Dentistry doctor is online; 0 Neurology doctors are online
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-den-online',
            name: 'Dr. Kavya Rao',
            specialty: 'Dentistry',
            qualification: 'BDS',
            experienceYears: 6,
            rating: 0,
            reviewCount: 0,
            clinicName: 'City Care',
            phone: '9111100001',
            email: 'kavya@care.in',
            status: 'Online',
            onlineStatus: 'Online',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹500',
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: TalkToDentistNowScreen()),
          ),
        );
        await tester.pump();

        // Filter to Neurology -> 0 online
        await tester.tap(find.byKey(const Key('talk_specialty_chip_Neurology')));
        await tester.pump();
        expect(find.text('No doctors online right now'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('talk_to_dentist_concern_input')),
          'Severe recurring migraine for 4 days',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('talk_to_dentist_connect_button')));
        await tester.pumpAndSettle();

        // Must offer Coordinator Assistance instead of faking a match
        final coordBtn = find.byKey(const Key('talk_to_dentist_request_coordinator_button'));
        expect(coordBtn, findsOneWidget);
        await tester.tap(coordBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(service.requests.length, 1);
        expect(service.requests.first.status, equals('Submitted'));
        expect(service.requests.first.problemCategory, contains('Neurology'));
      },
    );

    testWidgets(
      '2. BookConsultationFab appears on Patient screens (preserving specialty), and never on AuthScreen',
      (tester) async {
        tester.view.physicalSize = const Size(430, 960);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-fab-1',
          name: 'Rohit Verma',
          phone: '9888877776',
          age: '32',
          gender: 'Male',
          pincode: '500081',
          photoBytes: _testPng,
        );

        // Auth screen must NOT show the Patient Book Consultation FAB
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: AuthScreen()),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('book_consultation_fab')), findsNothing);

        // Patient Dashboard shows Book a Consultation FAB
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: PatientDashboardScreen()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('book_consultation_fab')), findsOneWidget);
        expect(find.text('Book a Consultation'), findsOneWidget);

        // FindDoctorsScreen shows FAB and preserves selected specialty ('Cardiology') in BookVisitFlowDialog
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(initialSpecialty: 'Cardiology'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('book_consultation_fab')), findsOneWidget);

        await tester.tap(find.byKey(const Key('book_consultation_fab')));
        await tester.pumpAndSettle();
        expect(find.byType(BookVisitFlowDialog), findsOneWidget);

        // Close dialog, then verify AiTriageScreen also shows BookConsultationFab
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: AiTriageScreen(initialSpecialty: 'Neurology'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('book_consultation_fab')), findsOneWidget);
      },
    );
  });
}
