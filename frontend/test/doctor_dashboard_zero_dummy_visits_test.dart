import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String todayYmd() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugFetchAppointmentsOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  Future<void> loginAsDoctor(
    PatientProblemService service, {
    required String dentistId,
    required String userId,
    required String name,
    required String email,
  }) async {
    await SessionService().saveSession(
      token: 'doc-jwt-$dentistId',
      role: 'Dentist',
      userId: userId,
      name: name,
      email: email,
      phone: '9876543210',
    );
    service.registerDoctor(
      id: dentistId,
      userId: userId,
      name: name,
      specialty: 'Cardiology',
      qualification: 'MBBS, MD',
      experienceYears: 5,
      clinicName: 'GS HEALTH Clinic',
      phone: '9876543210',
      email: email,
      licenseNumber: 'MED-$dentistId',
      skipApiRegister: true,
    );
  }

  group('GS Health Doctor Dashboard – Zero Dummy Visits & Strict Doctor Isolation', () {
    testWidgets(
      '1 & 5. Newly registered doctor with 0 appointments sees 0/0/0 stats, clean empty state, and NEVER sees other doctors visits or unrelated platform patients',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = PatientProblemService();
        // Seed another doctor's appointment AND unrelated platform patients
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'other-doc-appt-1',
            patientId: 'pat-other-1',
            patientName: 'Unrelated Patient Rahul',
            patientPhone: '9876599999',
            problemCategory: 'Dentistry',
            problemDescription: 'Tooth cleaning for Doctor B',
            preferredLocation: 'Other Clinic',
            severity: 'Mild',
            submittedAt: DateTime.now(),
            confirmedDate: todayYmd(),
            confirmedTimeSlot: '10:00 AM',
            assignedDoctorId: 'doc-other-99',
            assignedDoctorName: 'Dr. Other Specialist',
            status: 'CONFIRMED',
          ),
        );
        service.addTestPatient(
          PatientProfile(
            id: 'pat-unrelated-2',
            name: 'Random Platform User',
            phone: '9111122222',
            city: 'Hyderabad',
          ),
        );

        await loginAsDoctor(
          service,
          dentistId: 'doc-brand-new-1',
          userId: 'usr-brand-new-1',
          name: 'Dr. Fresh Register',
          email: 'fresh@gshealth.in',
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: DentistTimelineScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Summary KPIs must all be 0
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_upcoming_visits'))).data,
          equals('0'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_completed_visits'))).data,
          equals('0'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_total_patients'))).data,
          equals('0'),
        );

        // Clean empty state message shown
        expect(find.byKey(const Key('dentist_no_appointments_empty_state')), findsOneWidget);
        expect(find.text('No patient visits yet.'), findsOneWidget);
        expect(
          find.text('Your patient appointments will appear here once patients book a consultation.'),
          findsOneWidget,
        );

        // Other doctor's patient MUST NOT appear anywhere on Today tab
        expect(find.textContaining('Unrelated Patient Rahul'), findsNothing);

        // Switch to Patients tab -> MUST show "No patients yet" (never leak platform patients!)
        await tester.tap(find.text('Patients'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('No patients yet'), findsOneWidget);
        expect(find.textContaining('Unrelated Patient Rahul'), findsNothing);
        expect(find.textContaining('Random Platform User'), findsNothing);
      },
    );

    testWidgets(
      '2, 3, 4 & 5. Doctor with 1 and multiple real appointments (upcoming + completed) sees accurate counts & visits while excluding other doctors',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final service = PatientProblemService();
        await loginAsDoctor(
          service,
          dentistId: 'doc-real-1',
          userId: 'usr-real-1',
          name: 'Dr. Kavitha Rao',
          email: 'kavitha@gshealth.in',
        );

        // 1. Add ONE real upcoming appointment for Dr. Kavitha Rao
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'appt-kav-1',
            patientId: 'pat-real-1',
            patientName: 'Sita Devi',
            patientPhone: '9876510001',
            problemCategory: 'Cardiology',
            problemDescription: 'ECG consultation',
            preferredLocation: 'GS HEALTH Clinic',
            severity: 'Moderate',
            submittedAt: DateTime.now(),
            confirmedDate: todayYmd(),
            confirmedTimeSlot: '11:00 AM',
            assignedDoctorId: 'doc-real-1',
            assignedDoctorName: 'Dr. Kavitha Rao',
            status: 'CONFIRMED',
          ),
        );

        // Also seed another doctor's appointment to verify strict isolation
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'appt-other-doc',
            patientId: 'pat-other-x',
            patientName: 'Hidden Other Patient',
            patientPhone: '9876599000',
            problemCategory: 'Dermatology',
            problemDescription: 'Skin check',
            preferredLocation: 'Other Clinic',
            severity: 'Mild',
            submittedAt: DateTime.now(),
            confirmedDate: todayYmd(),
            confirmedTimeSlot: '11:30 AM',
            assignedDoctorId: 'doc-other-2',
            assignedDoctorName: 'Dr. Someone Else',
            status: 'CONFIRMED',
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: DentistTimelineScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Scenario 2: 1 real appointment -> Upcoming: 1, Completed: 0, Total Patients: 1
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_upcoming_visits'))).data,
          equals('1'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_completed_visits'))).data,
          equals('0'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_total_patients'))).data,
          equals('1'),
        );
        expect(find.textContaining('Sita Devi'), findsWidgets);
        expect(find.textContaining('Hidden Other Patient'), findsNothing);

        // Scenario 3 & 4: Add a 2nd rescheduled appointment & a 3rd COMPLETED appointment
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'appt-kav-2',
            patientId: 'pat-real-2',
            patientName: 'Arjun Nair',
            patientPhone: '9876510002',
            problemCategory: 'Cardiology',
            problemDescription: 'BP follow-up',
            preferredLocation: 'GS HEALTH Clinic',
            severity: 'Mild',
            submittedAt: DateTime.now(),
            confirmedDate: todayYmd(),
            confirmedTimeSlot: '02:00 PM',
            assignedDoctorId: 'doc-real-1',
            assignedDoctorName: 'Dr. Kavitha Rao',
            status: 'RESCHEDULED',
          ),
        );
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'appt-kav-3',
            patientId: 'pat-real-3',
            patientName: 'Meera Iyer',
            patientPhone: '9876510003',
            problemCategory: 'Cardiology',
            problemDescription: 'Completed echo review',
            preferredLocation: 'GS HEALTH Clinic',
            severity: 'Mild',
            submittedAt: DateTime.now().subtract(const Duration(hours: 3)),
            confirmedDate: todayYmd(),
            confirmedTimeSlot: '09:00 AM',
            assignedDoctorId: 'doc-real-1',
            assignedDoctorName: 'Dr. Kavitha Rao',
            status: 'COMPLETED',
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_upcoming_visits'))).data,
          equals('2'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_completed_visits'))).data,
          equals('1'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('doctor_stat_total_patients'))).data,
          equals('3'),
        );

        // Filter to Previous (Completed visits) -> shows Meera Iyer, hides upcoming-only
        final prevChip = find.byKey(const Key('doctor_visit_filter_Previous'));
        await tester.ensureVisible(prevChip);
        await tester.tap(prevChip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.textContaining('Meera Iyer'), findsWidgets);
        expect(find.textContaining('Hidden Other Patient'), findsNothing);
      },
    );
  });
}
