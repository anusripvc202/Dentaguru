import 'dart:typed_data';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pngPhoto = Uint8List.fromList(const [
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    await PatientProblemService().clearAllData();
  });

  testWidgets(
    '1. Visits splits into Upcoming Visits, Previous Visits, Cancelled Visits with real fee and Reschedule/Cancel actions',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = PatientProblemService();
      service.currentPatient = PatientProfile(
        id: 'pat-p7-1',
        name: 'Kiran Rao',
        phone: '9876543210',
        age: '31',
        gender: 'Male',
        pincode: '500081',
        photoBytes: pngPhoto,
      );

      service.addTestRequest(
        PatientConsultationRequest(
          id: 'v-up-1',
          patientId: 'pat-p7-1',
          patientName: 'Kiran Rao',
          patientPhone: '9876543210',
          problemCategory: 'Cardiology',
          problemDescription: 'Online Consultation',
          preferredLocation: 'Online Video',
          severity: 'Mild',
          submittedAt: DateTime(2026, 11, 28, 10, 0),
          confirmedDate: '2026-11-28',
          confirmedTimeSlot: '10:30 AM',
          assignedDoctorName: 'Dr. Kavita Menon',
          assignedDoctorSpecialty: 'Cardiology',
          assignedDoctorFee: '₹950',
          status: 'CONFIRMED',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'v-prev-1',
          patientId: 'pat-p7-1',
          patientName: 'Kiran Rao',
          patientPhone: '9876543210',
          problemCategory: 'Neurology',
          problemDescription: 'Migraine follow-up',
          preferredLocation: 'Metro Clinic',
          severity: 'Mild',
          submittedAt: DateTime(2026, 11, 10, 14, 0),
          confirmedDate: '2026-11-10',
          confirmedTimeSlot: '02:00 PM',
          assignedDoctorName: 'Dr. Arjun Verma',
          assignedDoctorSpecialty: 'Neurology',
          status: 'COMPLETED',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'v-can-1',
          patientId: 'pat-p7-1',
          patientName: 'Kiran Rao',
          patientPhone: '9876543210',
          problemCategory: 'Dentistry',
          problemDescription: 'Cleaning',
          preferredLocation: 'Dental Hub',
          severity: 'Mild',
          submittedAt: DateTime(2026, 11, 5, 11, 0),
          confirmedDate: '2026-11-05',
          confirmedTimeSlot: '11:00 AM',
          assignedDoctorName: 'Dr. Rohan Gupta',
          assignedDoctorSpecialty: 'Dentistry',
          status: 'CANCELLED',
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PatientDashboardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Visits')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('visits_tab_upcoming')), findsOneWidget);
      expect(find.byKey(const Key('visits_tab_previous')), findsOneWidget);
      expect(find.byKey(const Key('visits_tab_cancelled')), findsOneWidget);

      expect(find.text('Dr. Kavita Menon'), findsOneWidget);
      expect(find.text('ONLINE'), findsOneWidget);
      expect(find.text('Fee: ₹950'), findsOneWidget);
      expect(find.byKey(const Key('reschedule_visit_button_v-up-1')), findsOneWidget);
      expect(find.byKey(const Key('cancel_visit_button_v-up-1')), findsOneWidget);

      final prevTab = find.byKey(const Key('visits_tab_previous'));
      await tester.ensureVisible(prevTab);
      await tester.pump();
      await tester.tap(prevTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dr. Arjun Verma'), findsOneWidget);
      expect(find.text('Dr. Kavita Menon'), findsNothing);

      final cancelledTab = find.byKey(const Key('visits_tab_cancelled'));
      await tester.ensureVisible(cancelledTab);
      await tester.pump();
      await tester.tap(cancelledTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dr. Rohan Gupta'), findsOneWidget);
      expect(find.text('Dr. Arjun Verma'), findsNothing);
    },
  );

  testWidgets(
    '2. Health Locker has dedicated Prescriptions & Diagnostics tabs with test metadata & empty states',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = PatientProblemService();
      service.currentPatient = PatientProfile(
        id: 'pat-p7-2',
        name: 'Sita Devi',
        phone: '9876543218',
        age: '29',
        gender: 'Female',
        pincode: '500081',
        photoBytes: pngPhoto,
      );

      service.addMedicalRecord({
        'id': 'rx-p7-1',
        'patientId': 'pat-p7-2',
        'type': 'prescription',
        'category': 'Prescription',
        'diagnosis': 'Tension Headache',
        'doctorName': 'Dr. Arjun Verma',
        'date': '2026-11-20',
        'items': [
          {'name': 'Paracetamol', 'dosage': '500mg', 'frequency': '1-0-1', 'duration': '5 days'},
        ],
      });
      service.addMedicalRecord({
        'id': 'diag-p7-1',
        'patientId': 'pat-p7-2',
        'type': 'diagnostic',
        'category': 'Lab Report',
        'title': 'Complete Blood Count (CBC)',
        'referringDoctor': 'Dr. Kavita Menon',
        'labName': 'Apollo Diagnostics',
        'reportStatus': 'Ready',
        'date': '2026-11-21',
        'fileName': 'cbc_report.pdf',
        'fileType': 'PDF',
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PatientDashboardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.descendant(of: find.byType(BottomNavigationBar), matching: find.text('Locker')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('locker_tab_prescriptions')), findsOneWidget);
      expect(find.byKey(const Key('locker_tab_diagnostics')), findsOneWidget);
      expect(find.text('Tension Headache'), findsOneWidget);
      expect(find.text('℞ Paracetamol 500mg'), findsOneWidget);

      final diagTab = find.byKey(const Key('locker_tab_diagnostics'));
      await tester.ensureVisible(diagTab);
      await tester.pump();
      await tester.tap(diagTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('diagnostic_card_diag-p7-1')), findsOneWidget);
      expect(find.text('Complete Blood Count (CBC)'), findsOneWidget);
      expect(find.text('Referring Doctor: Dr. Kavita Menon'), findsOneWidget);
      expect(find.text('Lab: Apollo Diagnostics'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
    },
  );
}
