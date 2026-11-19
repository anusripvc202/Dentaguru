import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/patient/presentation/screens/doctor_profile_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PatientProblemService service;

  DoctorModel makeTestDoctor({
    required String id,
    required String name,
    required String status,
  }) {
    return DoctorModel(
      id: id,
      userId: 'user-$id',
      name: name,
      specialty: 'Cardiology',
      qualification: 'MBBS, MD, DM (Cardiology)',
      experienceYears: 10,
      rating: 4.9,
      reviewCount: 42,
      clinicName: 'GS Heart Center',
      phone: '9876543210',
      email: '$id@gshealth.test',
      status: status,
      verificationStatus: 'VERIFIED',
      nextAvailableSlots: const ['10:00 AM', '11:00 AM'],
      consultationFee: '₹800',
      city: 'Hyderabad',
      state: 'Telangana',
      pincode: '500032',
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = PatientProblemService();
    await service.clearAllData();
  });

  tearDown(() async {
    await service.clearAllData();
  });

  group('Doctor Availability ON/OFF Flutter UI & Visibility', () {
    testWidgets('1. Doctor ON is visible in FindDoctorsScreen; Doctor OFF is immediately hidden for patients', (tester) async {
      final docOn = makeTestDoctor(id: 'doc-1', name: 'Dr. Aarav Reddy', status: 'Available');
      final docOff = makeTestDoctor(id: 'doc-2', name: 'Dr. Meera Nair', status: 'Unavailable');
      service.addTestDoctor(docOn);
      service.addTestDoctor(docOff);

      expect(service.availableDoctors.map((d) => d.id).toList(), ['doc-1']);

      await tester.pumpWidget(
        const MaterialApp(
          home: FindDoctorsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dr. Aarav Reddy'), findsOneWidget);
      expect(find.text('Dr. Meera Nair'), findsNothing);

      // Admin view still sees both ON and OFF doctors for management
      await tester.pumpWidget(
        const MaterialApp(
          home: FindDoctorsScreen(isAdminView: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dr. Aarav Reddy'), findsOneWidget);
      expect(find.text('Dr. Meera Nair'), findsOneWidget);
    });

    testWidgets('2. Doctor OFF hides details & shows "Doctor is currently unavailable" on bookmarked DoctorProfileScreen for patients', (tester) async {
      final docOff = makeTestDoctor(id: 'doc-off', name: 'Dr. Priya Sharma', status: 'Unavailable');
      service.addTestDoctor(docOff);

      await tester.pumpWidget(
        MaterialApp(
          home: DoctorProfileScreen(doctor: docOff),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('doctor_unavailable_state')), findsOneWidget);
      expect(find.text('Doctor is currently unavailable'), findsOneWidget);
      // Profile details must NOT be exposed to patient
      expect(find.text('GS Heart Center'), findsNothing);
      expect(find.text('MBBS, MD, DM (Cardiology)'), findsNothing);
    });

    testWidgets('3. Doctor ON again restores profile visibility in DoctorProfileScreen', (tester) async {
      final docOn = makeTestDoctor(id: 'doc-toggle', name: 'Dr. Vikram Rao', status: 'Available');
      service.addTestDoctor(docOn);

      await tester.pumpWidget(
        MaterialApp(
          home: DoctorProfileScreen(doctor: docOn),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('doctor_unavailable_state')), findsNothing);
      expect(find.text('Dr. Vikram Rao'), findsOneWidget);
      expect(find.text('GS Heart Center'), findsOneWidget);
    });

    testWidgets('4. Doctor Dashboard renders clear Availability ON/OFF switch and status badge', (tester) async {
      final doc = makeTestDoctor(id: 'doc-dash', name: 'Dr. Kavya Menon', status: 'Available');
      service.addTestDoctor(doc);
      service.currentDoctor = doc;

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DentistTimelineScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('dentist_availability_card')), findsOneWidget);
      expect(find.byKey(const Key('dentist_availability_switch')), findsOneWidget);
      expect(find.byKey(const Key('dentist_availability_status_badge')), findsOneWidget);
      expect(find.text('ON'), findsOneWidget);
    });
  });
}
