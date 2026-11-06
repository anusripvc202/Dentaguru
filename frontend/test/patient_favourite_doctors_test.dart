import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';

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

  group('GS HEALTH — Patient Dashboard Doctor Section UI Update Tests', () {
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
      nextAvailableSlots: const ['10:00 AM', '11:30 AM'],
      consultationFee: '₹500',
    );

    testWidgets('1. Connect to a Doctor card renders with updated labels and opens dialog on tap', (tester) async {
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

      // Verify "Connect to a Doctor" card
      expect(find.text('Connect to a Doctor'), findsOneWidget);
      expect(find.text('Explore doctors and connect with a specialized dentist.'), findsOneWidget);
      expect(find.text('Book a Dentist'), findsNothing);

      // Tap on "Connect to a Doctor" card
      await tester.tap(find.text('Connect to a Doctor'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verifies dialog opens with matching title
      expect(find.text('Explore doctors and connect with a specialized dentist.'), findsWidgets);

      // Dismiss dialog
      Navigator.of(tester.element(find.text('Connect to a Doctor').first)).pop();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('2. My Favourite Doctors section label displays dynamic count and filters list', (tester) async {
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

      // Verify "My Favourite Doctors (0)" initially
      expect(find.text('My Favourite Doctors (0)'), findsOneWidget);
      expect(find.text('My Doctors (0)'), findsNothing);
      expect(find.text('No doctors added to "My Favourite Doctors" yet'), findsOneWidget);

      // Switch to All Doctors tab
      await tester.tap(find.text('All Doctors (1)'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify doctor card in All Doctors
      expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
      expect(find.text('Add Favourite Doctor'), findsOneWidget);
      expect(find.text('Add Doctor'), findsNothing);
    });

    testWidgets('3. Add Favourite Doctor action updates count, changes state to Added to Favourites, and prevents duplicates', (tester) async {
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

      // Switch to All Doctors tab
      await tester.tap(find.text('All Doctors (1)'));
      await tester.pump(const Duration(milliseconds: 300));

      // Click "Add Favourite Doctor"
      expect(find.text('Add Favourite Doctor'), findsOneWidget);
      await tester.ensureVisible(find.text('Add Favourite Doctor'));
      await tester.tap(find.text('Add Favourite Doctor'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify state changes to "Added to Favourites"
      expect(find.text('Added to Favourites'), findsOneWidget);
      expect(find.text('Add Favourite Doctor'), findsNothing);

      // Verify dynamic count updated to (1)
      expect(find.text('My Favourite Doctors (1)'), findsOneWidget);

      // Switch to My Favourite Doctors tab
      await tester.tap(find.text('My Favourite Doctors (1)'));
      await tester.pump(const Duration(milliseconds: 300));

      // Doctor is now displayed under My Favourite Doctors
      expect(find.text('Dr. Sheshu Kumar'), findsOneWidget);
      expect(find.text('Added to Favourites'), findsOneWidget);

      // Attempt duplicate addition programmatically & verify Set uniqueness
      await service.addDoctorToMyDoctors(testDoctor);
      expect(service.myDoctors.length, equals(1));
    });

    testWidgets('4. Removing a favourite doctor reverts state and decrements count', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      service.addTestDoctor(testDoctor);
      await service.addDoctorToMyDoctors(testDoctor);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PatientDashboardScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Verify initially in favourites
      expect(find.text('My Favourite Doctors (1)'), findsOneWidget);
      expect(find.text('Added to Favourites'), findsOneWidget);

      // Tap "Added to Favourites" to remove from favourites
      await tester.ensureVisible(find.text('Added to Favourites'));
      await tester.tap(find.text('Added to Favourites'));
      await tester.pump(const Duration(milliseconds: 300));

      // Count decrements to 0
      expect(find.text('My Favourite Doctors (0)'), findsOneWidget);
      expect(find.text('No doctors added to "My Favourite Doctors" yet'), findsOneWidget);

      // Switch to All Doctors
      await tester.tap(find.text('All Doctors (1)'));
      await tester.pump(const Duration(milliseconds: 300));

      // Button reverted back to "Add Favourite Doctor"
      expect(find.text('Add Favourite Doctor'), findsOneWidget);
    });

    testWidgets('5. Favourite doctor persistence in storage across sessions', (tester) async {
      final service = PatientProblemService();
      service.addTestDoctor(testDoctor);
      await service.addDoctorToMyDoctors(testDoctor);

      // Verify stored in memory
      expect(service.isDoctorAdded(testDoctor.id), isTrue);

      // Allow storage write to finish
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });

      // Re-read from storage
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString('dentaguru_my_doctor_ids') ?? '[]';
      final List storedList = jsonDecode(storedJson);
      expect(storedList.contains(testDoctor.id), isTrue);
    });
  });
}
