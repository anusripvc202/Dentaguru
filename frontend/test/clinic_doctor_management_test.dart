import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/doctor_profile_screen.dart';

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

  group('GS HEALTH — Clinic Dashboard: Add & Manage Doctors Tests', () {
    final cardiologyDoctor = DoctorModel(
      id: 'doc-cardio-101',
      userId: 'usr-cardio-101',
      name: 'Dr. Arjun Varma',
      specialty: 'Cardiology',
      qualification: 'MBBS, MD, DM',
      experienceYears: 10,
      rating: 4.9,
      reviewCount: 30,
      clinicName: 'GS HEALTH Partner Clinic',
      phone: '9848012345',
      email: 'arjun@gshealth.com',
      status: 'Available',
      city: 'Hyderabad',
      pincode: '500034',
      clinicAddress: 'Banjara Hills Road 10',
      bio: 'Senior Cardiologist specializing in preventive heart health.',
      nextAvailableSlots: const ['09:00 AM', '11:30 AM'],
      consultationFee: '₹800',
    );

    final independentDoctor = DoctorModel(
      id: 'doc-ind-202',
      userId: 'usr-ind-202',
      name: 'Dr. Priya Sharma',
      specialty: 'Dermatology',
      qualification: 'MBBS, MD (Dermatology)',
      experienceYears: 7,
      rating: 4.8,
      reviewCount: 22,
      clinicName: 'Independent Practice',
      phone: '9876500000',
      email: 'priya@dermatology.org',
      status: 'Available',
      city: 'Hyderabad',
      pincode: '500081',
      clinicAddress: 'Hitec City',
      bio: 'Consultant Dermatologist and aesthetic specialist.',
      nextAvailableSlots: const ['10:00 AM', '02:00 PM'],
      consultationFee: '₹600',
    );

    testWidgets(
      '1. Clinic Dashboard Doctors tab displays + Add Doctor button and opens Add Attached Doctor dialog with full form fields',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(cardiologyDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClinicDashboardScreen(),
            ),
          ),
        );
        await tester.pump();

        // Switch to Doctors tab
        await tester.tap(find.text('Doctors'));
        await tester.pumpAndSettle();

        // Verify + Add Doctor button
        expect(find.byKey(const Key('clinic_add_doctor_button')), findsOneWidget);
        expect(find.text('Add Doctor'), findsOneWidget);

        // Click Add Doctor button
        await tester.tap(find.byKey(const Key('clinic_add_doctor_button')));
        await tester.pumpAndSettle();

        // Verify dialog with title and required form fields
        expect(find.text('Add Attached Doctor'), findsOneWidget);
        expect(find.text('Doctor Full Name *'), findsOneWidget);
        expect(find.text('Mobile Number *'), findsOneWidget);
        expect(find.text('Email Address'), findsOneWidget);
        expect(find.text('Medical Specialty *'), findsOneWidget);
        expect(find.text('Registration / License No.'), findsOneWidget);
        expect(find.text('Available Consultation Days:'), findsOneWidget);
        expect(find.text('Available Consultation Slots:'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Clinic Doctors List displays Doctor Profile Image, Name, Specialty, Active/Inactive badge, and View Profile action',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(cardiologyDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClinicDashboardScreen(),
            ),
          ),
        );
        await tester.pump();

        // Switch to Doctors tab
        await tester.tap(find.text('Doctors'));
        await tester.pumpAndSettle();

        // Verify doctor card elements
        expect(find.byKey(Key('clinic_doctor_card_${cardiologyDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('clinic_doctor_image_${cardiologyDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('clinic_doctor_name_${cardiologyDoctor.id}')), findsOneWidget);
        expect(find.text('Dr. Arjun Varma'), findsOneWidget);
        expect(find.text('Cardiology'), findsWidgets);
        expect(find.text('Active'), findsOneWidget);
        expect(find.byKey(Key('clinic_view_profile_${cardiologyDoctor.id}')), findsOneWidget);
        expect(find.text('View Profile'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Clicking View Profile on Clinic Doctors List navigates to complete DoctorProfileScreen in clinic view',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(cardiologyDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClinicDashboardScreen(),
            ),
          ),
        );
        await tester.pump();

        // Switch to Doctors tab
        await tester.tap(find.text('Doctors'));
        await tester.pumpAndSettle();

        // Tap View Profile button
        await tester.tap(find.byKey(Key('clinic_view_profile_${cardiologyDoctor.id}')));
        await tester.pumpAndSettle();

        // Verify DoctorProfileScreen is opened in clinic view
        expect(find.byType(DoctorProfileScreen), findsOneWidget);
        expect(find.text('Doctor Profile'), findsOneWidget);
        expect(find.text('Dr. Arjun Varma'), findsOneWidget);
        expect(find.text('Cardiology'), findsWidgets);
        expect(find.text('MBBS, MD, DM'), findsWidgets);
        expect(find.byKey(const Key('clinic_doctor_management_card')), findsOneWidget);
        expect(find.byKey(const Key('clinic_edit_doctor_button')), findsOneWidget);
        expect(find.byKey(const Key('clinic_configure_slots_button')), findsOneWidget);
        expect(find.byKey(const Key('book_appointment_button')), findsNothing);
      },
    );

    testWidgets(
      '4. Add Doctor dialog detects existing GS HEALTH doctor and allows association without creating duplicate account',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(independentDoctor); // Registered previously under Independent Practice

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClinicDashboardScreen(),
            ),
          ),
        );
        await tester.pump();

        // Switch to Doctors tab
        await tester.tap(find.text('Doctors'));
        await tester.pumpAndSettle();

        // Open Add Doctor dialog
        await tester.tap(find.byKey(const Key('clinic_add_doctor_button')));
        await tester.pumpAndSettle();

        // Enter existing doctor's phone number
        await tester.enterText(find.widgetWithText(TextField, 'Mobile Number *'), '9876500000');
        await tester.pump();

        // Verify detection banner
        expect(find.textContaining('Existing GS HEALTH Doctor Found: Dr. Priya Sharma'), findsOneWidget);
        expect(find.byKey(const Key('clinic_associate_existing_doctor_button')), findsOneWidget);

        // Tap Associate Existing Doctor
        await tester.tap(find.byKey(const Key('clinic_associate_existing_doctor_button')));
        await tester.pumpAndSettle();

        // Verify doctor is now associated with the clinic
        final updatedDoc = service.allDoctors.firstWhere((d) => d.id == independentDoctor.id);
        expect(updatedDoc.clinicName, contains('GS HEALTH'));
      },
    );

    testWidgets(
      '5. Clinic Admin can activate/deactivate doctor and remove doctor from clinic while preserving global account',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(cardiologyDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClinicDashboardScreen(),
            ),
          ),
        );
        await tester.pump();

        // Switch to Doctors tab
        await tester.tap(find.text('Doctors'));
        await tester.pumpAndSettle();

        // Toggle status: Active -> Inactive
        expect(find.text('Active'), findsOneWidget);
        await tester.tap(find.byKey(Key('clinic_status_toggle_${cardiologyDoctor.id}')));
        await tester.pumpAndSettle();

        final deactivatedDoc = service.allDoctors.firstWhere((d) => d.id == cardiologyDoctor.id);
        expect(deactivatedDoc.status, equals('Inactive'));

        // Remove Doctor from Clinic
        await tester.tap(find.byKey(Key('clinic_remove_button_${cardiologyDoctor.id}')));
        await tester.pumpAndSettle();

        expect(find.text('Remove Doctor from Clinic'), findsOneWidget);
        expect(
          find.textContaining('This will disassociate the doctor from this clinic without deleting the doctor\'s global GS HEALTH account'),
          findsOneWidget,
        );

        // Confirm removal
        await tester.tap(find.byKey(const Key('confirm_remove_doctor_button')));
        await tester.pumpAndSettle();

        // Verify doctor global account still exists in platform
        final stillExists = service.allDoctors.any((d) => d.id == cardiologyDoctor.id);
        expect(stillExists, isTrue);
        final removedFromClinicDoc = service.allDoctors.firstWhere((d) => d.id == cardiologyDoctor.id);
        expect(removedFromClinicDoc.clinicName, equals('Independent Practice'));
      },
    );

    testWidgets(
      '6. Appointment Management displays doctor-wise schedules and detects overlapping appointment slots',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(cardiologyDoctor);

        // Add two conflicting appointments for Dr. Arjun Varma on the same date and slot
        final now = DateTime.now();
        final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        service.addTestRequest(
          PatientConsultationRequest(
            id: 'conflicting-appt-1',
            patientName: 'Patient Alice',
            patientPhone: '9000000001',
            problemCategory: 'Cardiology',
            problemDescription: 'Chest pain',
            severity: 'High',
            submittedAt: now,
            status: 'Confirmed',
            assignedDoctorId: cardiologyDoctor.id,
            assignedDoctorName: cardiologyDoctor.name,
            assignedDoctorClinic: cardiologyDoctor.clinicName,
            confirmedDate: dateStr,
            confirmedTimeSlot: '09:00 AM',
          ),
        );

        service.addTestRequest(
          PatientConsultationRequest(
            id: 'conflicting-appt-2',
            patientName: 'Patient Bob',
            patientPhone: '9000000002',
            problemCategory: 'Cardiology',
            problemDescription: 'Hypertension checkup',
            severity: 'Moderate',
            submittedAt: now,
            status: 'Confirmed',
            assignedDoctorId: cardiologyDoctor.id,
            assignedDoctorName: cardiologyDoctor.name,
            assignedDoctorClinic: cardiologyDoctor.clinicName,
            confirmedDate: dateStr,
            confirmedTimeSlot: '09:00 AM', // Same slot!
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ClinicDashboardScreen(),
            ),
          ),
        );
        await tester.pump();

        // Switch to Appointments tab
        await tester.tap(find.text('Appointments'));
        await tester.pumpAndSettle();

        // Verify Appointments are displayed
        expect(find.text('Patient Alice • Cardiology'), findsOneWidget);
        expect(find.text('Patient Bob • Cardiology'), findsOneWidget);

        // Verify Overlapping Slot Alert banner and conflict indicator
        expect(find.text('Overlapping Slot Alert Detected'), findsOneWidget);
        expect(find.text('Overlapping Slot Conflict with another patient'), findsWidgets);
      },
    );
  });
}

