import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiService.debugFetchAppointmentsOverride = null;
    await SessionService().clearSession();
    final service = PatientProblemService();
    await service.clearAllData();
    service.setDentistMode(false);
    service.setAdminMode(false);
  });

  tearDown(() async {
    ApiService.debugFetchAppointmentsOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  String datePlusDays(int days) {
    final dt = DateTime.now().add(Duration(days: days));
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> pumpPatientDashboard(
    WidgetTester tester, {
    required Size viewportSize,
  }) async {
    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: false),
          home: const PatientDashboardScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('Patient Dashboard Hero Appointment Card – Dynamic Doctor Name', () {
    testWidgets(
      '1. Fetches appointments by logged-in patient ID, ignores other patients, selects next chronological appointment among multiple doctors & renders Dr. name below title',
      (tester) async {
        final service = PatientProblemService();
        const loggedInPatientId = 'pat-anu-58df98d2';
        service.currentPatient = PatientProfile(
          id: loggedInPatientId,
          name: 'Anu',
          phone: '9063663180',
          email: 'anu@gshealth.test',
          city: 'Hyderabad',
          pincode: '500081',
        );

        String? requestedPatientId;
        final tomorrow = datePlusDays(1);
        final inFiveDays = datePlusDays(5);

        ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async {
          requestedPatientId = patientId;
          return [
            // Another patient's earlier appointment — MUST NOT be shown to Anu
            {
              'id': 'appt-other-patient',
              'patient_id': 'pat-other-999',
              'patient_name': 'Other Patient',
              'dentist_id': 'doc-other',
              'dentist_name': 'Dr. Wrong Doctor',
              'treatment': 'Orthopedic Review',
              'status': 'CONFIRMED',
              'date': '${tomorrow}T00:00:00Z',
              'time_slot': '08:00 AM',
            },
            // Later date appointment for Anu
            {
              'id': 'appt-anu-later-day',
              'patient_id': loggedInPatientId,
              'patient_name': 'Anu',
              'dentist_id': 'doc-vikram',
              'dentist_name': 'Dr. Vikram Cardio',
              'treatment': 'Cardiac Follow-up',
              'status': 'CONFIRMED',
              'date': '${inFiveDays}T00:00:00Z',
              'time_slot': '11:00 AM',
            },
            // Same day afternoon appointment for Anu
            {
              'id': 'appt-anu-afternoon',
              'patient_id': loggedInPatientId,
              'patient_name': 'Anu',
              'dentist_id': 'doc-rohitha',
              'dentist_name': 'Dr. Rohitha',
              'treatment': 'Dermatology Review',
              'status': 'CONFIRMED',
              'date': '${tomorrow}T00:00:00Z',
              'time_slot': '02:30 PM',
            },
            // Soonest upcoming appointment for Anu (tomorrow 09:30 AM)
            {
              'id': 'appt-anu-soonest',
              'patient_id': loggedInPatientId,
              'patient_name': 'Anu',
              'dentist_id': 'doc-sri',
              'dentist_name': 'sri', // tests clean "Dr. " prefixing without duplication
              'treatment': 'General Consultation',
              'status': 'CONFIRMED',
              'date': '${tomorrow}T00:00:00Z',
              'time_slot': '09:30 AM',
            },
          ];
        };

        await pumpPatientDashboard(tester, viewportSize: const Size(390, 844));

        expect(requestedPatientId, equals(loggedInPatientId));
        expect(find.text('YOUR SMILE, CARED FOR'), findsOneWidget);

        final titleFinder = find.byKey(const Key('hero_appointment_title'));
        final doctorFinder = find.byKey(const Key('hero_appointment_doctor_name'));
        final statusTimeFinder = find.byKey(const Key('hero_appointment_status_time'));

        expect(titleFinder, findsOneWidget);
        expect(doctorFinder, findsOneWidget);
        expect(statusTimeFinder, findsOneWidget);

        expect((tester.widget<Text>(titleFinder)).data, equals('General Consultation'));
        expect((tester.widget<Text>(doctorFinder)).data, equals('Dr. sri'));
        expect((tester.widget<Text>(statusTimeFinder)).data, equals('Confirmed for 09:30 AM'));

        // Verify strict visual ordering: Title above Doctor Name, Doctor Name above Status/Time
        final titleTop = tester.getTopLeft(titleFinder).dy;
        final doctorTop = tester.getTopLeft(doctorFinder).dy;
        final statusTop = tester.getTopLeft(statusTimeFinder).dy;
        expect(doctorTop, greaterThan(titleTop));
        expect(statusTop, greaterThan(doctorTop));

        // Must never display another patient's appointment doctor
        expect(find.text('Dr. Wrong Doctor'), findsNothing);
      },
    );

    testWidgets(
      '2. Completed or cancelled appointments are excluded; Hero advances to next doctor and falls back to empty state when none remain (mobile + desktop)',
      (tester) async {
        final service = PatientProblemService();
        const loggedInPatientId = 'pat-anu-58df98d2';
        service.currentPatient = PatientProfile(
          id: loggedInPatientId,
          name: 'Anu',
          phone: '9063663180',
          email: 'anu@gshealth.test',
        );

        final tomorrow = datePlusDays(1);
        final dayAfter = datePlusDays(2);

        List<Map<String, dynamic>> serverRows = [
          {
            'id': 'appt-1',
            'patient_id': loggedInPatientId,
            'patient_name': 'Anu',
            'dentist_id': 'doc-sri',
            'dentist_name': 'Dr. sri',
            'treatment': 'General Consultation',
            'status': 'COMPLETED', // Completed -> must NOT show
            'date': '${tomorrow}T00:00:00Z',
            'time_slot': '09:30 AM',
          },
          {
            'id': 'appt-2',
            'patient_id': loggedInPatientId,
            'patient_name': 'Anu',
            'dentist_id': 'doc-kiran',
            'dentist_name': 'Dr. Kiran',
            'treatment': 'Orthopedic Consult',
            'status': 'CANCELLED', // Cancelled -> must NOT show
            'date': '${tomorrow}T00:00:00Z',
            'time_slot': '10:30 AM',
          },
          {
            'id': 'appt-3',
            'patient_id': loggedInPatientId,
            'patient_name': 'Anu',
            'dentist_id': 'doc-rohitha',
            'dentist_name': 'Dr. Rohitha',
            'treatment': 'Dermatology Checkup',
            'status': 'CONFIRMED',
            'date': '${dayAfter}T00:00:00Z',
            'time_slot': '04:00 PM',
          },
        ];

        ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async {
          return serverRows;
        };

        // Desktop viewport check (1280x800)
        await pumpPatientDashboard(tester, viewportSize: const Size(1280, 800));

        expect(
          tester.widget<Text>(find.byKey(const Key('hero_appointment_title'))).data,
          equals('Dermatology Checkup'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('hero_appointment_doctor_name'))).data,
          equals('Dr. Rohitha'),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('hero_appointment_status_time'))).data,
          equals('Confirmed for 04:00 PM'),
        );

        // Now mark the remaining appointment CANCELLED -> Hero must revert to default empty state
        serverRows = [
          ...serverRows.take(2),
          {
            ...serverRows[2],
            'status': 'CANCELLED',
          },
        ];
        await service.syncAppointmentsFromApi();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          tester.widget<Text>(find.byKey(const Key('hero_appointment_title'))).data,
          equals('No upcoming visits'),
        );
        expect(find.byKey(const Key('hero_appointment_doctor_name')), findsNothing);
        expect(
          tester.widget<Text>(find.byKey(const Key('hero_appointment_status_time'))).data,
          equals('Book a verified doctor near you in under a minute.'),
        );
      },
    );
  });
}
