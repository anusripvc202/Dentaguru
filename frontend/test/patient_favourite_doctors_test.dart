import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
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

  group('GS HEALTH — Find Doctors Navigation & Doctor Profile Pages Tests', () {
    final testDoctor = DoctorModel(
      id: 'doc-fav-001',
      userId: 'usr-fav-001',
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
      bio: 'Senior Periodontics and Implantology specialist dedicated to minimally invasive gum care.',
      nextAvailableSlots: const ['10:00 AM', '11:30 AM'],
      consultationFee: '₹500',
    );

    testWidgets(
      '1. Patient Dashboard does NOT display doctor list inline and clicking Find Doctors opens separate FindDoctorsScreen',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(testDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Verify doctor list is NOT rendered inline below Patient Dashboard
        expect(find.byType(FindDoctorsScreen), findsNothing);
        expect(find.text('Dental Specialists & Doctors'), findsNothing);
        expect(find.text('View Profile'), findsNothing);

        // Tap "Find Doctors" quick action on Patient Dashboard
        expect(find.text('Find Doctors'), findsOneWidget);
        await tester.tap(find.text('Find Doctors'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify navigation to separate FindDoctorsScreen
        expect(find.byType(FindDoctorsScreen), findsOneWidget);
        expect(find.text('Discover Dental Specialists'), findsOneWidget);
        expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
        expect(find.text('Periodontics'), findsWidgets);
        expect(find.text('BDS, MDS'), findsOneWidget);
        expect(find.text('5+ yrs exp'), findsOneWidget);
        expect(find.textContaining('Kakaji Dental Clinic'), findsOneWidget);
        expect(find.text('View Profile'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Full Navigation Flow: Patient Dashboard -> Find Doctors -> Select Doctor -> Doctor Details -> Select Date & Slot -> Book Appointment -> Back Navigation',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(testDoctor);

        // Pre-book 10:00 AM today to verify booked vs available slot distinction
        final now = DateTime.now();
        final todayStr =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'existing-appt-1',
            patientName: 'Existing Patient',
            patientPhone: '9000000001',
            problemCategory: 'General Consultation',
            problemDescription: 'Routine checkup',
            severity: 'Low',
            submittedAt: now,
            status: 'Confirmed',
            assignedDoctorId: testDoctor.id,
            assignedDoctorName: testDoctor.name,
            confirmedDate: todayStr,
            confirmedTimeSlot: '10:00 AM',
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Step 1: Patient Dashboard -> Find Doctors
        await tester.tap(find.text('Find Doctors'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(FindDoctorsScreen), findsOneWidget);

        // Step 2: Select Doctor (via View Profile button) -> Doctor Details Page
        await tester.tap(find.byKey(Key('view_profile_button_${testDoctor.id}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(DoctorProfileScreen), findsOneWidget);

        // Verify Doctor Information on Doctor Details Page
        expect(find.text('Doctor Details'), findsOneWidget);
        expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
        expect(find.text('Periodontics'), findsOneWidget);
        expect(find.text('BDS, MDS'), findsWidgets);
        expect(find.text('5+ Years'), findsOneWidget);
        expect(
          find.text('Senior Periodontics and Implantology specialist dedicated to minimally invasive gum care.'),
          findsOneWidget,
        );
        expect(find.text('Kakaji Dental Clinic'), findsOneWidget);
        expect(find.text('Kakaji colony, Hanamkonda'), findsOneWidget);
        expect(find.text('Warangal, 506001'), findsOneWidget);
        expect(find.text('8977906566'), findsOneWidget);
        expect(find.text('sheshu@dentaguru.com'), findsOneWidget);

        // Verify Appointment Availability slots: 10:00 AM is Booked, 11:30 AM is Available
        expect(find.text('10:00 AM (Booked)'), findsOneWidget);
        expect(find.text('11:30 AM'), findsOneWidget);

        // Clicking booked slot should NOT select it
        await tester.tap(find.byKey(const Key('time_slot_10:00 AM')));
        await tester.pump();
        expect(find.text('Book Appointment (10:00 AM)'), findsNothing);

        // Step 3: Select Available Time Slot (11:30 AM)
        await tester.ensureVisible(find.byKey(const Key('time_slot_11:30 AM')));
        await tester.tap(find.byKey(const Key('time_slot_11:30 AM')));
        await tester.pump();
        expect(find.text('Book Appointment (11:30 AM)'), findsOneWidget);

        // Step 4: Click Book Appointment
        final bookBtn = find.byKey(const Key('book_appointment_button'));
        await tester.ensureVisible(bookBtn);
        await tester.tap(bookBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify booking confirmation dialog appears
        expect(find.text('Appointment Booked!'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify inline confirmation banner & slot now marked Booked (preventing double booking)
        expect(find.text('Appointment Confirmed'), findsOneWidget);
        expect(find.text('11:30 AM (Booked)'), findsOneWidget);

        // Step 5: Back button on Doctor Details -> Find Doctors
        await tester.tap(find.byKey(const Key('back_to_find_doctors_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(FindDoctorsScreen), findsOneWidget);

        // Step 6: Back button on Find Doctors -> Patient Dashboard
        await tester.tap(find.byKey(const Key('back_to_patient_dashboard_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(PatientDashboardScreen), findsOneWidget);
        expect(find.byType(FindDoctorsScreen), findsNothing);
      },
    );

    testWidgets(
      '3. Clicking doctor name or doctor profile image on FindDoctorsScreen also navigates to DoctorProfileScreen',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(testDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Doctor Name -> navigates to DoctorProfileScreen
        await tester.tap(find.byKey(Key('doctor_name_${testDoctor.id}')));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(find.byType(DoctorProfileScreen), findsOneWidget);

        // Navigate back to FindDoctorsScreen
        await tester.tap(find.byKey(const Key('back_to_find_doctors_button')));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(find.byType(FindDoctorsScreen), findsOneWidget);

        // Tap Doctor Image -> navigates to DoctorProfileScreen
        await tester.tap(find.byKey(Key('doctor_image_${testDoctor.id}')));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(find.byType(DoctorProfileScreen), findsOneWidget);
      },
    );

    testWidgets(
      '4. Add and Remove Favourite Doctor on FindDoctorsScreen updates count and persists to storage',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(testDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('All Doctors (1)'), findsOneWidget);
        expect(find.text('My Favourite Doctors (0)'), findsOneWidget);

        // Click "Add Favourite Doctor"
        await tester.tap(find.text('Add Favourite Doctor'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Added to Favourites'), findsOneWidget);
        expect(find.text('My Favourite Doctors (1)'), findsOneWidget);

        // Verify stored in SharedPreferences
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 200));
        });
        final prefs = await SharedPreferences.getInstance();
        final storedJson = prefs.getString('dentaguru_my_doctor_ids') ?? '[]';
        final List storedList = jsonDecode(storedJson);
        expect(storedList.contains(testDoctor.id), isTrue);

        // Remove from favourites
        await tester.tap(find.text('Added to Favourites'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('My Favourite Doctors (0)'), findsOneWidget);
        expect(find.text('Add Favourite Doctor'), findsOneWidget);
      },
    );
  });
}
