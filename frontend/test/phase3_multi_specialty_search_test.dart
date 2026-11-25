import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/models/medical_specialty_model.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    await PatientProblemService().clearAllData();
  });

  group('Phase 3: Multi-Specialty Doctor Search & Strict Specialty Isolation', () {
    test('1. Strict canonical specialty matching never leaks unrelated specialties or blank defaults', () {
      // Blank specialty never matches specific filters
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('', 'Dentistry'), isFalse);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('', 'Neurology'), isFalse);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('', 'All'), isTrue);

      // General Physician / MBBS <-> General Medicine, NEVER General Dentistry
      expect(
        MedicalSpecialtyModel.matchesSpecialtyFilter('General Medicine', 'General Physician / MBBS'),
        isTrue,
      );
      expect(
        MedicalSpecialtyModel.matchesSpecialtyFilter('General Physician / MBBS', 'General Medicine'),
        isTrue,
      );
      expect(
        MedicalSpecialtyModel.matchesSpecialtyFilter('General Dentistry', 'General Physician / MBBS'),
        isFalse,
      );
      expect(
        MedicalSpecialtyModel.matchesSpecialtyFilter('General Dentist', 'General Medicine'),
        isFalse,
      );

      // Orthopedics NEVER matches Orthodontics, and vice versa
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Orthodontics', 'Orthopedics'), isFalse);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Orthopedics', 'Orthodontics'), isFalse);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Orthodontics', 'Dentistry'), isTrue);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Orthopedics', 'Dentistry'), isFalse);

      // Neurology & Cardiology strict isolation
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Neurology', 'Neurology'), isTrue);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Cardiology', 'Neurology'), isFalse);
      expect(MedicalSpecialtyModel.matchesSpecialtyFilter('Dentistry', 'Neurology'), isFalse);
    });

    testWidgets(
      '2. FindDoctorsScreen surfaces Neurology, Cardiology, General Physician / MBBS, Dentistry, enforces strict filtering, supports Online filter, and renders real Doctor Card details',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-neuro-1',
            name: 'Dr. Sanjay Kulkarni',
            specialty: 'Neurology',
            qualification: 'MBBS, MD, DM (Neurology)',
            experienceYears: 14,
            rating: 0.0,
            reviewCount: 0,
            clinicName: 'Brain & Spine Institute',
            city: 'Hyderabad',
            pincode: '500033',
            phone: '9000010001',
            email: 'sanjay@neuro.in',
            status: 'Online',
            onlineStatus: 'Online',
            nextAvailableSlots: const ['10:30 AM'],
            consultationFee: '₹1,000',
            languages: const ['English', 'Telugu'],
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-cardio-1',
            name: 'Dr. Meenakshi Iyer',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM (Cardiology)',
            experienceYears: 11,
            rating: 4.9,
            reviewCount: 28,
            clinicName: 'Metro Heart Hospital',
            city: 'Bengaluru',
            pincode: '560001',
            phone: '9000010002',
            email: 'meenakshi@heart.in',
            status: 'Available',
            onlineStatus: 'Offline',
            nextAvailableSlots: const ['04:00 PM'],
            consultationFee: '₹900',
            languages: const ['English', 'Kannada', 'Tamil'],
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-gp-1',
            name: 'Dr. Farhan Siddiqui',
            specialty: 'General Medicine',
            qualification: 'MBBS, MD',
            experienceYears: 8,
            rating: 0.0,
            reviewCount: 0,
            clinicName: 'City Primary Care',
            city: 'Hyderabad',
            pincode: '500081',
            phone: '9000010003',
            email: 'farhan@care.in',
            status: 'Online',
            onlineStatus: 'Online',
            nextAvailableSlots: const ['11:15 AM'],
            consultationFee: '₹550',
            languages: const ['English', 'Hindi', 'Urdu'],
          ),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-dent-1',
            name: 'Dr. Swathi Rao',
            specialty: 'Orthodontics',
            qualification: 'BDS, MDS',
            experienceYears: 6,
            rating: 0.0,
            reviewCount: 0,
            clinicName: 'Smile Align Clinic',
            city: 'Hyderabad',
            pincode: '500034',
            phone: '9000010004',
            email: 'swathi@smile.in',
            status: 'Busy',
            onlineStatus: 'Busy',
            nextAvailableSlots: const ['05:30 PM'],
            consultationFee: '₹650',
            languages: const ['English', 'Telugu'],
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const FindDoctorsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Core 4 specialties exist in pill row
        expect(find.byKey(const Key('specialty_chip_Neurology')), findsOneWidget);
        expect(find.byKey(const Key('specialty_chip_Cardiology')), findsOneWidget);
        expect(find.byKey(const Key('specialty_chip_General Physician / MBBS')), findsOneWidget);
        expect(find.byKey(const Key('specialty_chip_Dentistry')), findsOneWidget);

        // Doctor card real fields: fee, experience, next slot, online dot, no fake 5.0 rating on 0-review doctor
        expect(find.byKey(const Key('doctor_fee_doc-neuro-1')), findsOneWidget);
        expect(find.text('Fee: ₹1,000'), findsOneWidget);
        expect(find.text('Next: 10:30 AM'), findsOneWidget);
        expect(find.textContaining('14 yrs exp'), findsOneWidget);
        expect(find.byKey(const Key('doctor_online_dot_doc-neuro-1')), findsOneWidget);
        expect(find.textContaining('★ 4.9 (28)'), findsOneWidget);
        expect(find.textContaining('★ 5.0 (0)'), findsNothing);

        // Filter by Neurology -> ONLY Dr. Sanjay Kulkarni
        await tester.tap(find.byKey(const Key('specialty_chip_Neurology')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Sanjay Kulkarni'), findsOneWidget);
        expect(find.text('Dr. Meenakshi Iyer'), findsNothing);
        expect(find.text('Dr. Farhan Siddiqui'), findsNothing);
        expect(find.text('Dr. Swathi Rao'), findsNothing);

        // Filter by General Physician / MBBS -> ONLY Dr. Farhan Siddiqui (never Dentist!)
        await tester.ensureVisible(find.byKey(const Key('specialty_chip_General Physician / MBBS')));
        await tester.tap(find.byKey(const Key('specialty_chip_General Physician / MBBS')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Farhan Siddiqui'), findsOneWidget);
        expect(find.text('Dr. Swathi Rao'), findsNothing);
        expect(find.text('Dr. Sanjay Kulkarni'), findsNothing);

        // Filter by Dentistry -> ONLY Dr. Swathi Rao (Orthodontics)
        final specScroll = find.byKey(const Key('specialty_filter_scroll_view'));
        await tester.drag(specScroll, const Offset(-200, 0));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('specialty_chip_Dentistry')));
        await tester.tap(find.byKey(const Key('specialty_chip_Dentistry')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Swathi Rao'), findsOneWidget);
        expect(find.text('Dr. Farhan Siddiqui'), findsNothing);

        // Reset specialty to All, then enable "Available Online" filter -> only Online doctors (Sanjay & Farhan)
        await tester.drag(specScroll, const Offset(400, 0));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('specialty_chip_All')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('specialty_chip_All')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('online_availability_filter_chip')));
        await tester.pumpAndSettle();
        expect(find.text('Dr. Sanjay Kulkarni'), findsOneWidget);
        expect(find.text('Dr. Farhan Siddiqui'), findsOneWidget);
        // Meenakshi has onlineStatus: 'Offline' (schedule Available, presence Offline) and Swathi is 'Busy'
        expect(find.text('Dr. Meenakshi Iyer'), findsNothing);
        expect(find.text('Dr. Swathi Rao'), findsNothing);
      },
    );
  });
}
