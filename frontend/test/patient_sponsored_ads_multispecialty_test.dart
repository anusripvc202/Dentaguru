import 'dart:typed_data';
import 'package:dentaguru/core/models/medical_specialty_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/patient/presentation/screens/ai_triage_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/find_doctors_screen.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/widgets/gs_health_patient_sponsored_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async => [];
    ApiService.debugFetchDoctorLanguagesOverride = ({bool includeUnavailable = false}) async => ['English', 'Hindi'];
    ApiService.debugFetchDentistsOverride = ({
      String? state,
      String? city,
      String? pincode,
      String? specialty,
      String? availability,
      String? language,
      List<String>? languages,
      String? search,
      bool includeUnavailable = false,
    }) async =>
        [
          {
            'id': 'doc-cardio-1',
            'name': 'Dr. Vikram Cardio',
            'specialty': 'Cardiology',
            'specialization': 'Cardiology',
            'qualification': 'MBBS, MD, DM',
            'experience_years': 10,
            'rating': 4.9,
            'review_count': 20,
            'clinic_name': 'GS Heart Center',
            'phone': '9988776655',
            'email': 'vikram@gshealth.test',
            'status': 'Available',
            'is_available': true,
            'availability': true,
            'next_available_slots': ['10:00 AM'],
            'consultation_fee': '₹900',
            'languages': ['English', 'Hindi'],
          },
        ];
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchNotificationsOverride = null;
    ApiService.debugFetchDoctorLanguagesOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    await PatientProblemService().clearAllData();
  });

  group('GS HEALTH Patient Dashboard Multi-Specialty Sponsored Advertisements', () {
    test('1. buildDynamicAds excludes dental-only ads and reflects active available specialties', () {
      final specialties = [
        const MedicalSpecialtyModel(
          id: 's-gen',
          code: 'GEN_MED',
          name: 'General Medicine',
          department: 'General Medicine',
          description: 'Primary care',
          isActive: true,
          displayOrder: 1,
        ),
        const MedicalSpecialtyModel(
          id: 's-cardio',
          code: 'CARDIO',
          name: 'Cardiology',
          department: 'Cardiology',
          description: 'Heart care',
          isActive: true,
          displayOrder: 2,
        ),
        const MedicalSpecialtyModel(
          id: 's-derm',
          code: 'DERM',
          name: 'Dermatology',
          department: 'Dermatology',
          description: 'Skin care',
          isActive: false, // Inactive -> must NOT appear
          displayOrder: 3,
        ),
        const MedicalSpecialtyModel(
          id: 's-dental',
          code: 'DENTAL',
          name: 'Dentistry',
          department: 'Dentistry',
          description: 'Dental implants and oral care',
          isActive: true, // Dental-only -> must NOT appear in general patient sponsored section
          displayOrder: 4,
        ),
        const MedicalSpecialtyModel(
          id: 's-nephro',
          code: 'NEPHRO',
          name: 'Nephrology', // Admin-added future specialty
          department: 'Department of Nephrology',
          description: 'Kidney wellness and hypertension follow-up.',
          isActive: true,
          displayOrder: 5,
        ),
      ];

      // Without doctor availability filtering (all active non-dental specialties)
      final allActiveAds = GsHealthPatientSponsoredBanner.buildDynamicAds(
        activeSpecialties: specialties,
        availableDoctors: const [],
      );
      final titles = allActiveAds.map((a) => a.title).toList();
      expect(titles, contains('GS HEALTH'));
      expect(titles, contains('GS HEALTH DIGITAL CARE'));
      expect(titles, contains('GS HEALTH PRIMARY CARE'));
      expect(titles, contains('GS HEALTH CARDIOLOGY'));
      expect(titles, contains('GS HEALTH NEPHROLOGY'));
      expect(titles.any((t) => t.contains('IMPLANT') || t.contains('DENT')), isFalse);
      expect(titles.any((t) => t.contains('DERMATOLOGY')), isFalse); // inactive

      // When doctors are registered & available ONLY for Cardiology -> omit unrelated specialties
      final cardioDoctor = DoctorModel(
        id: 'doc-cardio-1',
        name: 'Dr. Vikram Cardio',
        specialty: 'Cardiology',
        qualification: 'MBBS, MD, DM',
        experienceYears: 10,
        rating: 4.9,
        reviewCount: 20,
        clinicName: 'GS Heart Center',
        phone: '9988776655',
        email: 'vikram@gshealth.test',
        status: 'Available',
        nextAvailableSlots: const ['10:00 AM'],
        consultationFee: '₹900',
      );
      final filteredAds = GsHealthPatientSponsoredBanner.buildDynamicAds(
        activeSpecialties: specialties,
        availableDoctors: [cardioDoctor],
      );
      final filteredTitles = filteredAds.map((a) => a.title).toList();
      expect(filteredTitles, contains('GS HEALTH'));
      expect(filteredTitles, contains('GS HEALTH DIGITAL CARE'));
      expect(filteredTitles, contains('GS HEALTH CARDIOLOGY'));
      expect(filteredTitles, isNot(contains('GS HEALTH NEPHROLOGY')));
      expect(filteredTitles, isNot(contains('GS HEALTH PRIMARY CARE')));
    });

    testWidgets(
      '2. PatientDashboardScreen renders GS HEALTH multi-specialty sponsored banner in official Navy Blue & Orange with equal balance, removes GS IMPLANTS, navigates to destinations & avoids overflow on narrow viewports',
      (tester) async {
        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-1',
          name: 'Anu',
          phone: '9063663180',
          age: '28',
          gender: 'Female',
          pincode: '500081',
          photoBytes: Uint8List.fromList(const [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82,
          ]),
        );
        service.addTestDoctor(
          DoctorModel(
            id: 'doc-cardio-1',
            name: 'Dr. Vikram Cardio',
            specialty: 'Cardiology',
            qualification: 'MBBS, MD, DM',
            experienceYears: 10,
            rating: 4.9,
            reviewCount: 20,
            clinicName: 'GS Heart Center',
            phone: '9988776655',
            email: 'vikram@gshealth.test',
            status: 'Available',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹900',
          ),
        );

        for (final viewport in [const Size(320, 700), const Size(390, 844), const Size(1280, 900)]) {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(useMaterial3: false),
                home: const PatientDashboardScreen(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          // Verify dental-only ad is completely removed
          expect(find.text('GS IMPLANTS'), findsNothing);
          expect(find.text('Most economic dental implants'), findsNothing);
          expect(find.text('DEDICATED TO EXCELLENCE'), findsNothing);

          // Verify GS HEALTH card structure preserved
          final bannerFinder = find.byKey(const Key('patient_sponsored_banner'));
          expect(bannerFinder, findsOneWidget);
          expect(find.text('SPONSORED'), findsOneWidget);
          expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);

          final titleText = tester.widget<Text>(find.byKey(const Key('patient_sponsored_title')));
          final subtitleText = tester.widget<Text>(find.byKey(const Key('patient_sponsored_subtitle')));
          final descText = tester.widget<Text>(find.byKey(const Key('patient_sponsored_description')));

          expect(titleText.data, equals('GS HEALTH'));
          expect(subtitleText.data, equals('COMPLETE HEALTHCARE SOLUTIONS'));
          expect(titleText.style?.color, equals(AppTheme.gsNavy));
          expect(subtitleText.style?.color, equals(AppTheme.brandOrange));
          expect(descText.style?.color, equals(AppTheme.gsNavy));

          expect(tester.takeException(), isNull);
        }

        // Cycle through ads -> Digital Care -> Cardiology
        await tester.ensureVisible(find.byKey(const Key('patient_sponsored_next_btn')));
        await tester.tap(find.byKey(const Key('patient_sponsored_next_btn')));
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(const Key('patient_sponsored_title'))).data,
          equals('GS HEALTH DIGITAL CARE'),
        );

        // Tap Digital Care -> navigates to AiTriageScreen
        await tester.tap(find.byKey(const Key('patient_sponsored_banner')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AiTriageScreen), findsOneWidget);

        // Return to PatientDashboardScreen
        Navigator.of(tester.element(find.byType(AiTriageScreen))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Cycle to Cardiology ad -> tap opens FindDoctorsScreen filtered to Cardiology
        await tester.ensureVisible(find.byKey(const Key('patient_sponsored_next_btn')));
        await tester.tap(find.byKey(const Key('patient_sponsored_next_btn')));
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(const Key('patient_sponsored_title'))).data,
          equals('GS HEALTH CARDIOLOGY'),
        );

        await tester.tap(find.byKey(const Key('patient_sponsored_banner')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(FindDoctorsScreen), findsOneWidget);
        expect(find.textContaining('Cardiology'), findsWidgets);
      },
    );
  });
}
