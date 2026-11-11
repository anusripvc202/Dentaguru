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
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';

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

  group('GS HEALTH — Unified Doctor Listing, Specialty Dropdown & Doctor Profile Pages Tests', () {
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

    final cardiologyDoctor = DoctorModel(
      id: 'doc-cardio-002',
      userId: 'usr-cardio-002',
      name: 'Dr. Rahul Sharma',
      specialty: 'Cardiology',
      qualification: 'MBBS, MD, DM (Cardiology)',
      experienceYears: 12,
      rating: 4.9,
      reviewCount: 88,
      clinicName: 'GS HEALTH Heart Care Center',
      phone: '9876543210',
      email: 'rahul@gshealth.com',
      status: 'Available',
      city: 'Hyderabad',
      pincode: '500018',
      clinicAddress: 'Banjara Hills, Road No 12',
      bio: 'Senior Interventional Cardiologist.',
      nextAvailableSlots: const ['09:00 AM', '02:00 PM'],
      consultationFee: '₹800',
    );

    testWidgets(
      '1. Patient Dashboard does NOT display doctor list inline and clicking Find Doctors opens separate FindDoctorsScreen with compact single-line rows',
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

        // Tap "Find Doctors" quick action on Patient Dashboard
        expect(find.text('Find Doctors'), findsOneWidget);
        await tester.tap(find.text('Find Doctors'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify navigation to separate FindDoctorsScreen
        expect(find.byType(FindDoctorsScreen), findsOneWidget);
        expect(find.text('Discover Healthcare Specialists'), findsOneWidget);

        // Verify compact single-line row contains ONLY Doctor Profile Image, Doctor Full Name, and right-arrow indicator
        expect(find.byKey(Key('doctor_card_${testDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('doctor_image_${testDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('doctor_name_${testDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('view_profile_button_${testDoctor.id}')), findsOneWidget);
        expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);

        // Verify qualifications, fees, experience, clinic details are NOT displayed in the listing
        expect(find.text('BDS, MDS'), findsNothing);
        expect(find.text('5+ yrs exp'), findsNothing);
        expect(find.textContaining('Kakaji Dental Clinic'), findsNothing);
        expect(find.text('₹500'), findsNothing);
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

        // Step 2: Select Doctor (via right-arrow indicator) -> Doctor Details Page
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

        // Verify Appointment Availability slots: ONLY published unbooked slots are displayed (10:00 AM is booked, so hidden)
        expect(find.byKey(const Key('time_slot_10:00 AM')), findsNothing);
        expect(find.text('10:00 AM (Booked)'), findsNothing);
        expect(find.text('11:30 AM'), findsOneWidget);

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

        // Verify inline confirmation banner & slot immediately removed from available slots (preventing double booking)
        expect(find.text('Appointment Confirmed'), findsOneWidget);
        expect(find.byKey(const Key('time_slot_11:30 AM')), findsNothing);

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
      '4. Add and Remove Favourite Doctor on DoctorProfileScreen updates count on FindDoctorsScreen and persists to storage',
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

        // Open DoctorProfileScreen
        await tester.tap(find.byKey(Key('doctor_card_${testDoctor.id}')));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(find.byType(DoctorProfileScreen), findsOneWidget);

        // Click "Add Favourite Doctor" on DoctorProfileScreen
        await tester.tap(find.text('Add Favourite Doctor'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Added to Favourites'), findsOneWidget);

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
        expect(find.text('Add Favourite Doctor'), findsOneWidget);
      },
    );

    testWidgets(
      '5. ALL Button Specialty Dropdown opens dynamic specialty menu and navigates to separate Specialty-Based Doctors Listing Page',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(testDoctor); // Periodontics (Dentistry)
        service.addTestDoctor(cardiologyDoctor); // Cardiology

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Initially both doctors are listed under All Specialties
        expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
        expect(find.text('Dr. Rahul Sharma'), findsOneWidget);

        // Click the ALL Specialty Dropdown button
        final allDropdownBtn = find.byKey(const Key('all_specialties_dropdown_button'));
        expect(allDropdownBtn, findsOneWidget);
        await tester.tap(allDropdownBtn);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        // Verify dynamic specialty categories appear in the dropdown menu
        expect(find.text('All Specialties'), findsOneWidget);
        expect(find.byKey(const Key('specialty_dropdown_item_Cardiology')), findsOneWidget);
        expect(find.byKey(const Key('specialty_dropdown_item_Dentistry')), findsOneWidget);

        // Select "Cardiology" -> Navigates to separate "Cardiology Doctors" page
        await tester.tap(find.byKey(const Key('specialty_dropdown_item_Cardiology')));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        // Verify separate Cardiology Doctors page shows ONLY Cardiology doctors in compact single-line format
        expect(find.text('Cardiology Doctors'), findsWidgets);
        expect(find.text('Dr. Rahul Sharma'), findsOneWidget);
        expect(find.text('Dr. Sheshu Kumar'), findsNothing);

        // Back button returns to main FindDoctorsScreen showing both doctors
        await tester.tap(find.byKey(const Key('back_to_patient_dashboard_button')));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
        expect(find.text('Dr. Rahul Sharma'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Admin Dashboard Doctors Listing uses compact single-line rows, + Create Doctor button, ALL dropdown, and Admin Doctor Profile Page',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.addTestDoctor(testDoctor);
        service.addTestDoctor(cardiologyDoctor);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: AdminDashboardScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Navigate to "Doctors" tab in Admin Dashboard
        await tester.ensureVisible(find.text('Doctors'));
        await tester.tap(find.text('Doctors'));
        await tester.pump(const Duration(milliseconds: 400));

        // Verify "+ Create Doctor" button and ALL Specialty Dropdown button
        expect(find.byKey(const Key('admin_create_doctor_button')), findsOneWidget);
        expect(find.text('+ Create Doctor'), findsOneWidget);
        expect(find.byKey(const Key('admin_all_specialties_dropdown_button')), findsOneWidget);

        // Verify compact single-line rows for doctors (no fees/qualifications inline)
        expect(find.byKey(Key('admin_doctor_card_${testDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('admin_doctor_image_${testDoctor.id}')), findsOneWidget);
        expect(find.byKey(Key('admin_doctor_name_${testDoctor.id}')), findsOneWidget);
        expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
        expect(find.text('Dr. Rahul Sharma'), findsOneWidget);
        expect(find.text('MBBS, MD, DM (Cardiology)'), findsNothing);

        // Tap doctor row -> navigates to separate DoctorProfileScreen in Admin mode
        await tester.ensureVisible(find.byKey(Key('admin_doctor_card_${cardiologyDoctor.id}')));
        await tester.tap(find.byKey(Key('admin_doctor_card_${cardiologyDoctor.id}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(DoctorProfileScreen), findsOneWidget);
        expect(find.text('Dr. Rahul Sharma'), findsOneWidget);
        expect(find.text('MBBS, MD, DM (Cardiology)'), findsWidgets);
        expect(find.text('GS HEALTH Heart Care Center'), findsOneWidget);

        // Verify Admin Doctor Management & Verification card is displayed (and Patient Book Appointment button is hidden)
        expect(find.byKey(const Key('admin_doctor_management_card')), findsOneWidget);
        expect(find.byKey(const Key('admin_edit_doctor_button')), findsOneWidget);
        expect(find.byKey(const Key('admin_configure_slots_button')), findsOneWidget);
        expect(find.byKey(const Key('admin_delete_doctor_button')), findsOneWidget);
        expect(find.byKey(const Key('book_appointment_button')), findsNothing);
      },
    );
  });
}
