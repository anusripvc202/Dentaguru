import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/models/doctor_availability.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/widgets/doctor_slot_management_dialog.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    final service = PatientProblemService();
    await service.clearAllData();
  });

  group('GS HEALTH — Doctor Slot Management & Availability Booking Tests', () {
    final testDoctor = DoctorModel(
      id: 'doc-slot-test-001',
      userId: 'usr-slot-test-001',
      name: 'Dr. Sheshu Kumar',
      specialty: 'Periodontics',
      qualification: 'BDS, MDS',
      experienceYears: 5,
      rating: 5.0,
      reviewCount: 42,
      clinicName: 'Kakaji Dental Clinic',
      phone: '8977906566',
      email: 'sheshu@dentaguru.com',
      status: 'Available',
      city: 'Warangal',
      pincode: '506001',
      clinicAddress: 'Kakaji colony, Hanamkonda',
      nextAvailableSlots: const ['09:30 AM', '10:00 AM', '10:30 AM', '11:00 AM'],
      consultationFee: '₹500',
    );

    test('1. DoctorAvailabilityModel parses and serializes correctly', () {
      final json = {
        'id': 'avail-1',
        'dentistId': 'doc-1',
        'date': '2026-11-15',
        'startTime': '09:00 AM',
        'endTime': '05:00 PM',
        'slotDurationMinutes': 30,
        'slots': ['09:00 AM', '09:30 AM'],
        'bookedSlots': ['09:00 AM'],
        'availableSlots': ['09:30 AM'],
        'isBlocked': false,
      };

      final model = DoctorAvailabilityModel.fromJson(json);
      expect(model.dentistId, 'doc-1');
      expect(model.allSlots, ['09:00 AM', '09:30 AM']);
      expect(model.bookedSlots, ['09:00 AM']);
      expect(model.availableSlots, ['09:30 AM']);
      expect(model.isBlocked, isFalse);

      final out = model.toJson();
      expect(out['dentistId'], 'doc-1');
      expect(out['slotDurationMinutes'], 30);
    });

    test('2. PatientProblemService generates non-overlapping slots correctly', () {
      final service = PatientProblemService();
      final slots = service.generateTimeSlots(
        startTime: '10:00 AM',
        endTime: '12:00 PM',
        durationMinutes: 30,
      );

      expect(slots, ['10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM']);
    });

    test('2b. PatientProblemService generates slots strictly excluding lunch/break hours', () {
      final service = PatientProblemService();
      final slots = service.generateTimeSlots(
        startTime: '11:00 AM',
        endTime: '03:00 PM',
        durationMinutes: 60,
        breakStartTime: '01:00 PM',
        breakEndTime: '02:00 PM',
      );

      expect(slots, ['11:00 AM', '12:00 PM', '02:00 PM']);
      expect(slots.contains('01:00 PM'), isFalse);
    });

    testWidgets('3. DoctorSlotManagementDialog allows admin to configure and generate slots with working days & breaks', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      service.addTestDoctor(testDoctor);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoctorSlotManagementDialog(
              initialDoctor: testDoctor,
              isDoctorSelfManage: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Doctor Slot Management'), findsOneWidget);
      expect(find.text('Configured Working Days'), findsOneWidget);
      expect(find.text('Include Break / Lunch Hours'), findsOneWidget);

      final autoGenBtn = find.text('Auto-Generate Slots from Hours');
      expect(autoGenBtn, findsOneWidget);
      await tester.ensureVisible(autoGenBtn);
      await tester.pumpAndSettle();

      // Tap Auto-Generate
      await tester.tap(autoGenBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Publish Doctor Schedule'), findsOneWidget);
    });

    testWidgets('4. BookVisitFlowDialog displays published doctor availability slots and handles selection', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      service.addTestDoctor(testDoctor);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookVisitFlowDialog(
              preselectedDoctor: testDoctor,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Should be on Step 2 (Date & Time Slot)
      expect(find.text('1. Select Appointment Date'), findsOneWidget);
      expect(find.text('2. Select Available Time Slot'), findsOneWidget);

      // Verify doctor's published slots appear
      expect(find.text('09:30 AM'), findsWidgets);
      expect(find.text('10:00 AM'), findsWidgets);

      // Tap on a slot
      await tester.tap(find.text('09:30 AM').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Next button becomes enabled
      expect(find.text('Next: Reason for Visit'), findsOneWidget);
      await tester.tap(find.text('Next: Reason for Visit'));
      await tester.pump(const Duration(milliseconds: 300));

      // Should move to Step 3 (Reason & Symptoms)
      expect(find.text('Dental Issue / Consultation Reason'), findsOneWidget);
    });

    testWidgets('5. DentistTimelineScreen renders dedicated Manage Availability section with action buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      service.addTestDoctor(testDoctor);
      service.currentDoctor = testDoctor;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DentistTimelineScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify the dedicated Manage Availability section heading exists
      expect(find.text('Manage Availability & Consultation Slots'), findsOneWidget);
      expect(find.byKey(const Key('doctor_manage_availability_btn')), findsOneWidget);
      expect(find.byKey(const Key('doctor_block_holiday_btn')), findsOneWidget);
    });
  });
}
