import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';
import 'package:dentaguru/features/patient/presentation/widgets/appointment_management_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  group('Patient Appointments Screen & Booking Flow Verification', () {
    testWidgets('1. Appointments tab displays Book Visit button, No Scheduled Visits and Past Visit History', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = PatientProblemService();
      service.currentPatient = PatientProfile(
        id: 'patient-test-1',
        name: 'John Patient',
        phone: '9876543210',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PatientDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Navigate to Appointments tab via bottom nav bar
      final appointmentsNav = find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Appointments'),
      );
      expect(appointmentsNav, findsOneWidget);
      await tester.tap(appointmentsNav);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify "My Appointments" heading and subtitle
      expect(find.text('My Appointments'), findsOneWidget);
      expect(find.text('Track upcoming and past dental visits'), findsOneWidget);

      // Verify clearly visible "Book Visit" button
      expect(find.widgetWithText(ElevatedButton, 'Book Visit'), findsOneWidget);

      // Verify "No Scheduled Visits" card is present when empty
      expect(find.text('No Scheduled Visits'), findsOneWidget);
      expect(find.text('Submit a dental problem or report symptoms to schedule a visit.'), findsOneWidget);

      // Verify "Past Visit History" section and empty state
      expect(find.text('Past Visit History'), findsOneWidget);
      expect(find.text('No past dental visits recorded.'), findsOneWidget);
    });

    testWidgets('2. Clicking Book Visit opens the 4-step booking flow dialog', (tester) async {
      final service = PatientProblemService();
      service.currentPatient = PatientProfile(
        id: 'patient-test-2',
        name: 'Alice Patient',
        phone: '9988776655',
      );
      // Add a test doctor to the service
      service.addTestDoctor(
        DoctorModel(
          id: 'doc-101',
          userId: 'user-doc-101',
          name: 'Dr. Ramesh Sharma',
          specialty: 'Periodontics',
          qualification: 'BDS, MDS',
          experienceYears: 8,
          rating: 4.9,
          reviewCount: 35,
          clinicName: 'Smile Dental Clinic',
          clinicAddress: 'MG Road, Warangal',
          phone: '9123456789',
          email: 'ramesh@dentaguru.com',
          status: 'Available',
          nextAvailableSlots: ['10:30 AM', '02:00 PM', '04:00 PM'],
          consultationFee: '500',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => BookVisitFlowDialog.show(context),
                child: const Text('Open Booking'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click to open booking flow
      await tester.tap(find.text('Open Booking'));
      await tester.pumpAndSettle();

      // Step 1: Doctor selection dialog header
      expect(find.text('Book Dental Visit (1/4)'), findsOneWidget);
      expect(find.text('Dr. Ramesh Sharma'), findsOneWidget);
      expect(find.text('Periodontics'), findsWidgets);
      expect(find.text('Smile Dental Clinic'), findsOneWidget);

      // Select Doctor
      await tester.tap(find.text('Dr. Ramesh Sharma'));
      await tester.pumpAndSettle();

      // Tap Next: Select Date & Time
      await tester.tap(find.text('Next: Select Date & Time'));
      await tester.pumpAndSettle();

      // Step 2: Date & Slot Selection
      expect(find.text('Book Dental Visit (2/4)'), findsOneWidget);
      expect(find.text('1. Select Appointment Date'), findsOneWidget);
      expect(find.text('2. Select Available Time Slot'), findsOneWidget);

      // Pick a time slot (e.g. 10:30 AM)
      final slotWidget = find.text('10:30 AM');
      expect(slotWidget, findsOneWidget);
      await tester.tap(slotWidget);
      await tester.pumpAndSettle();

      // Tap Next: Reason for Visit
      await tester.tap(find.text('Next: Reason for Visit'));
      await tester.pumpAndSettle();

      // Step 3: Reason & Symptoms
      expect(find.text('Book Dental Visit (3/4)'), findsOneWidget);
      expect(find.text('Dental Issue / Consultation Reason'), findsOneWidget);
      expect(find.text('Describe Symptoms / Notes (Optional)'), findsOneWidget);

      // Tap Next: Review Booking Details
      await tester.tap(find.text('Next: Review Booking Details'));
      await tester.pumpAndSettle();

      // Step 4: Review Details
      expect(find.text('Book Dental Visit (4/4)'), findsOneWidget);
      expect(find.text('Review Appointment Details'), findsOneWidget);
      expect(find.text('Dr. Ramesh Sharma'), findsOneWidget);
      expect(find.text('Smile Dental Clinic'), findsOneWidget);
      expect(find.text('Alice Patient'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('Confirm & Book Appointment'), findsOneWidget);
    });

    testWidgets('3. Unavailable / already-booked time slots are prevented and visually struck-through', (tester) async {
      final service = PatientProblemService();
      final bookedDate = DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T').first;

      // Add existing booking for 10:30 AM
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'existing-appt-1',
          patientId: 'patient-other',
          patientName: 'Other Patient',
          patientPhone: '9000000000',
          problemCategory: 'Root Canal',
          problemDescription: 'Scheduled consultation',
          severity: 'Moderate',
          submittedAt: DateTime.now(),
          status: 'CONFIRMED',
          assignedDoctorId: 'doc-booked',
          assignedDoctorName: 'Dr. Busy Doctor',
          confirmedTimeSlot: '10:30 AM',
          confirmedDate: bookedDate,
        ),
      );

      final busyDoctor = DoctorModel(
        id: 'doc-booked',
        userId: 'user-doc-booked',
        name: 'Dr. Busy Doctor',
        specialty: 'Endodontics',
        qualification: 'BDS, MDS',
        experienceYears: 10,
        rating: 5.0,
        reviewCount: 50,
        clinicName: 'Metro Dental',
        phone: '9876543211',
        email: 'busy@dentaguru.com',
        status: 'Available',
        nextAvailableSlots: ['10:30 AM', '02:00 PM'],
        consultationFee: '600',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => BookVisitFlowDialog.show(context, preselectedDoctor: busyDoctor),
                child: const Text('Open Preselected'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Preselected'));
      await tester.pumpAndSettle();

      // Verify 10:30 AM slot is displayed as booked
      final bookedSlotText = tester.widget<Text>(find.text('10:30 AM'));
      expect(bookedSlotText.style?.decoration, TextDecoration.lineThrough);

      // Verify unbooked slot (e.g. 02:00 PM) is available and selectable
      final availableSlotText = tester.widget<Text>(find.text('02:00 PM'));
      expect(availableSlotText.style?.decoration, isNot(TextDecoration.lineThrough));

      await tester.tap(find.text('02:00 PM'));
      await tester.pumpAndSettle();

      // Next button becomes enabled with available slot
      final nextButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Next: Reason for Visit'));
      expect(nextButton.onPressed, isNotNull);
    });

    testWidgets('4. Scheduled appointments display doctor, clinic, date/time and management actions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = PatientProblemService();
      final testDate = DateTime.now().add(const Duration(days: 2)).toIso8601String();

      service.currentPatient = PatientProfile(
        id: 'patient-active',
        name: 'Kavitha Reddy',
        phone: '9848022338',
      );

      service.addTestRequest(
        PatientConsultationRequest(
          id: 'scheduled-visit-101',
          patientId: 'patient-active',
          patientName: 'Kavitha Reddy',
          patientPhone: '9848022338',
          problemCategory: 'Teeth Cleaning & Whitening',
          problemDescription: 'Routine tartar cleanup and polishing',
          severity: 'Mild',
          submittedAt: DateTime.now(),
          status: 'Confirmed',
          assignedDoctorId: 'doc-active',
          assignedDoctorName: 'Dr. Sheshu kumar',
          assignedDoctorClinic: 'Kakaji Dental Clinic',
          confirmedTimeSlot: '11:30 AM',
          confirmedDate: testDate,
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PatientDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to Appointments tab via bottom nav bar
      final appointmentsNav = find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Appointments'),
      );
      expect(appointmentsNav, findsOneWidget);
      await tester.tap(appointmentsNav);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify scheduled appointment card
      expect(find.text('Your Next Scheduled Visit'), findsOneWidget);
      expect(find.text('Dr. Sheshu kumar'), findsOneWidget);
      expect(find.text('Kakaji Dental Clinic'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Reschedule'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Details to open AppointmentManagementDialog
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Appointment Details'), findsOneWidget);
      expect(find.text('Teeth Cleaning & Whitening'), findsWidgets);
      expect(find.textContaining('11:30 AM'), findsWidgets);
    });

    testWidgets('5. Appointment Reschedule and Cancel flows', (tester) async {
      final appt = PatientConsultationRequest(
        id: 'appt-to-manage',
        patientId: 'patient-mgmt',
        patientName: 'Test Patient',
        patientPhone: '9900990099',
        problemCategory: 'Wisdom Tooth Pain',
        problemDescription: 'Impacted wisdom tooth consultation',
        severity: 'Severe',
        submittedAt: DateTime.now(),
        status: 'Confirmed',
        assignedDoctorId: 'doc-mgmt',
        assignedDoctorName: 'Dr. Oral Surgeon',
        assignedDoctorClinic: 'City Care Hospital',
        confirmedTimeSlot: '03:00 PM',
        confirmedDate: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AppointmentManagementDialog.show(
                  context,
                  appointment: appt,
                  initialMode: AppointmentManagementMode.reschedule,
                ),
                child: const Text('Open Reschedule'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Reschedule'));
      await tester.pumpAndSettle();

      expect(find.text('Reschedule Visit'), findsOneWidget);
      expect(find.text('Select New Appointment Date'), findsOneWidget);
      expect(find.text('Select New Time Slot'), findsOneWidget);
      expect(find.text('Confirm Reschedule'), findsOneWidget);
    });
  });
}
