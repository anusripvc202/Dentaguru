import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_admin_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const samplePngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

  late PatientProblemService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    ApiService.debugAdminAppointmentsOverride = null;
    await service.clearAllData();
  });

  group('Admin Dashboard Selected Doctor Booking Details & Responsive Layout', () {
    test('1. AdminAppointmentItem.fromRow resolves exact selectedDoctor (Doctor A) with photo, specialty, clinic, and fallbacks', () {
      final rowA = {
        'id': 'appt-1',
        'patient_id': 'pat-1',
        'dentist_id': 'doc-a',
        'clinic_id': 'clinic-a',
        'date': '2026-11-22T00:00:00.000Z',
        'time_slot': '10:30 AM',
        'treatment': 'Cardiac Review',
        'status': 'CONFIRMED',
        'created_at': '2026-11-18T14:15:00.000Z',
        'patient': {'id': 'pat-1', 'name': 'Riya Sharma', 'phone': '9876543210'},
        'selectedDoctor': {
          'id': 'doc-a',
          'name': 'Dr. Aarav Reddy',
          'specialty': 'Cardiology',
          'profilePhoto': samplePngBase64,
          'clinicId': 'clinic-a',
          'clinicName': 'Apex Heart Center',
        },
        'clinic': {'id': 'clinic-a', 'clinic_name': 'Apex Heart Center'},
      };

      final itemA = AdminAppointmentItem.fromRow(rowA, patients: const [], doctors: const []);
      expect(itemA.patientName, 'Riya Sharma');
      expect(itemA.phone, '9876543210');
      expect(itemA.dentistId, 'doc-a');
      expect(itemA.dentistName, 'Dr. Aarav Reddy');
      expect(itemA.doctorSpecialty, 'Cardiology');
      expect(itemA.doctorPhotoBytes, isNotNull);
      expect(itemA.clinicName, 'Apex Heart Center');
      expect(itemA.timeSlot, '10:30 AM');
      expect(itemA.createdAtRaw, '2026-11-18T14:15:00.000Z');
      expect(itemA.status, 'CONFIRMED');

      // Missing doctor & patient info -> safe fallbacks instead of incorrect substitution
      final missingRow = {
        'id': 'appt-missing',
        'date': '2026-11-22T00:00:00.000Z',
        'time_slot': '04:00 PM',
        'status': 'PENDING',
      };
      final missingItem = AdminAppointmentItem.fromRow(missingRow, patients: const [], doctors: const []);
      expect(missingItem.patientName, 'Patient Unavailable');
      expect(missingItem.dentistName, isEmpty);
      expect(missingItem.clinicName, isEmpty);
    });

    testWidgets('2. Admin Appointments Panel shows Doctor A (never Doctor B) and zero overflow on Desktop, Tablet, and Mobile with long names', (tester) async {
      const longPatientName =
          'Venkata Subrahmanya Narasimha Murthy Patient With Extraordinarily Long Name';
      const longDoctorAName =
          'Dr. Aaravindranath Chandrashekhar Specialist Cardiologist Senior Consultant';
      const longClinicName =
          'GS Health Super Specialty Multi-Department Heart & Clinical Institute Hyderabad';

      // Even if a problem request for the same patient was later assigned to Doctor B,
      // the booked appointment MUST show Doctor A!
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'req-unrelated',
          patientId: 'pat-1',
          patientName: longPatientName,
          patientPhone: '9876543210',
          problemCategory: 'Orthopedics',
          problemDescription: 'Unrelated request',
          symptoms: '',
          severity: 'Low',
          submittedAt: DateTime(2026, 11, 18),
          status: 'Dentist Assigned',
          assignedDoctorId: 'doc-b',
          assignedDoctorName: 'Dr. Later Assigned Doctor B',
          confirmedTimeSlot: '05:00 PM',
        ),
      );

      final largeDataset = List.generate(12, (i) {
        return {
          'id': 'appt-$i',
          'patient_id': 'pat-$i',
          'dentist_id': 'doc-a',
          'clinic_id': 'clinic-a',
          'date': '2026-11-${(20 + (i % 8)).toString().padLeft(2, '0')}T00:00:00.000Z',
          'time_slot': '${9 + (i % 6)}:30 AM',
          'treatment': 'Specialist Consultation #$i',
          'status': i.isEven ? 'CONFIRMED' : 'PENDING',
          'created_at': '2026-11-18T12:${(10 + i).toString().padLeft(2, '0')}:00.000Z',
          'patient': {
            'id': 'pat-$i',
            'name': i == 0 ? longPatientName : 'Patient Record $i',
            'phone': '98765000${i.toString().padLeft(2, '0')}',
          },
          'selectedDoctor': {
            'id': 'doc-a',
            'name': i == 0 ? longDoctorAName : 'Dr. Aarav Doctor A',
            'specialty': 'Interventional Cardiology & Electrophysiology',
            'profilePhoto': samplePngBase64,
            'clinicId': 'clinic-a',
            'clinicName': longClinicName,
          },
          'clinic': {'id': 'clinic-a', 'clinic_name': longClinicName},
        };
      });

      ApiService.debugAdminAppointmentsOverride = () async => largeDataset;

      final overflowErrors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed') ||
            details.exceptionAsString().contains('RenderFlex')) {
          overflowErrors.add(details);
        }
        prevOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      // Test across Desktop (1440x900), Tablet (800x1024), and Mobile (360x800)
      for (final size in const [
        Size(1440, 900), // Desktop
        Size(800, 1024), // Tablet
        Size(360, 800),  // Mobile
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const MaterialApp(
            home: AdminDashboardScreen(initialTab: 4),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        // Selected Doctor A must be shown; Doctor B must NEVER be substituted
        expect(find.textContaining('Dr. Aaravindranath'), findsWidgets);
        expect(find.textContaining('Dr. Later Assigned Doctor B'), findsNothing);
        expect(find.textContaining('Interventional Cardiology'), findsWidgets);
        expect(find.textContaining('GS Health Super Specialty'), findsWidgets);
        expect(find.textContaining('9876500000'), findsWidgets);

        if (size.width >= 1400) {
          expect(find.byKey(const Key('admin_appointments_desktop_table')), findsOneWidget);
        } else {
          expect(find.byKey(const Key('admin_schedule_appointment_card_appt-0')), findsOneWidget);
        }

        // Also test Admin Overview tab (tab 0) at same viewport size
        await tester.pumpWidget(
          const MaterialApp(
            home: AdminDashboardScreen(initialTab: 0),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
      }

      tester.view.resetPhysicalSize();
      expect(overflowErrors, isEmpty, reason: 'Expected zero RenderFlex overflow errors across Desktop, Tablet, and Mobile');
    });
  });
}
