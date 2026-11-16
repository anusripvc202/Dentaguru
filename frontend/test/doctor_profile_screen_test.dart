import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/dentist/presentation/screens/doctor_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadRealFontsIfAvailable() async {
  try {
    final regularFile = File(r'C:\Windows\Fonts\segoeui.ttf');
    final boldFile = File(r'C:\Windows\Fonts\segoeuib.ttf');
    final semiboldFile = File(r'C:\Windows\Fonts\seguisb.ttf');
    if (regularFile.existsSync()) {
      final regBytes = regularFile.readAsBytesSync();
      final boldBytes = boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;
      final semiBytes = semiboldFile.existsSync() ? semiboldFile.readAsBytesSync() : boldBytes;

      for (final family in ['Roboto', 'Plus Jakarta Sans', 'Outfit', 'Segoe UI']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(regBytes).buffer)))
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(semiBytes).buffer)))
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(boldBytes).buffer)));
        await loader.load();
      }
    }

    final symbolFile = File(r'C:\Windows\Fonts\seguisym.ttf');
    if (symbolFile.existsSync()) {
      final symBytes = symbolFile.readAsBytesSync();
      final symLoader = FontLoader('Segoe UI Symbol')
        ..addFont(Future.value(ByteData.view(Uint8List.fromList(symBytes).buffer)));
      await symLoader.load();
    }
  } catch (_) {}
}

Future<void> _capturePngIfPossible(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String outputPath,
) async {
  for (final element in find.byType(Image).evaluate()) {
    final widget = element.widget as Image;
    await tester.runAsync(() async {
      try {
        await precacheImage(widget.image, element);
      } catch (_) {}
    });
  }
  await tester.pump();
  await tester.runAsync(() async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      await File(outputPath).writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {}
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const String artifactDir = r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PatientProblemService().clearAllDataAndStorage();
  });

  group('GS HEALTH - Doctor Profile Screen Tests', () {
    testWidgets('1. Doctor Profile displays all sections matching reference screenshots and captures visuals', (tester) async {
      final service = PatientProblemService();

      final testDoctor = DoctorModel(
        id: 'doc-ananya-rao',
        userId: 'user-ananya-rao',
        name: 'Dr. Ananya Rao',
        specialty: 'Endodontist',
        qualification: 'BDS, MDS (Endodontics)',
        experienceYears: 9,
        rating: 4.9,
        reviewCount: 42,
        clinicName: 'Bandra West Dental Clinic',
        phone: '+919000000001',
        email: 'ananya.rao@gshealth.in',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['Today, 2:00 PM', 'Tomorrow, 10:30 AM'],
        consultationFee: '₹800',
        languages: ['English', 'Hindi', 'Telugu'],
      );

      service.currentDoctor = testDoctor;
      service.addTestDoctor(testDoctor);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              body: RepaintBoundary(
                key: boundaryKey,
                child: const DoctorProfileScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Profile Header
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_back_button')), findsOneWidget);
      expect(find.text('Dr. Ananya Rao'), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('+919000000001'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_edit_button')), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);

      // 2. Languages You Consult In
      expect(find.text('LANGUAGES YOU CONSULT IN'), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_English')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Hindi')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Telugu')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Marathi')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Tamil')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Kannada')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Malayalam')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Bengali')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Gujarati')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Punjabi')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Urdu')), findsOneWidget);
      expect(find.byKey(const Key('doctor_language_chip_Odia')), findsOneWidget);

      // 3. Practice Details
      expect(find.text('PRACTICE'), findsOneWidget);
      expect(find.text('Endodontist'), findsOneWidget);
      expect(find.text('BDS, MDS (Endodontics)'), findsOneWidget);
      expect(find.text('Bandra West Dental Clinic'), findsOneWidget);
      expect(find.text('VERIFIED ON GS HEALTH'), findsOneWidget);

      // Capture top screenshot (Screenshot 1 reference)
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir\\gs_health_doctor_profile_top.png',
      );

      // 4. Scroll down to inspect Menu, Need Help, and Account Actions (Screenshot 2 reference)
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Profile Menu Items
      expect(find.byKey(const Key('doctor_profile_referrals_button')), findsOneWidget);
      expect(find.text('Referrals'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_refer_specialist_button')), findsOneWidget);
      expect(find.text('Refer to a specialist or clinic'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_reviews_button')), findsOneWidget);
      expect(find.text('Patient reviews'), findsOneWidget);

      // Need Help Card
      expect(find.text('NEED HELP?'), findsOneWidget);
      expect(
        find.text('Call our 24/7 clinical care helpline for dental emergencies, appointments and consultations.'),
        findsOneWidget,
      );

      // Account Actions
      expect(find.byKey(const Key('doctor_profile_logout_button')), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_terms_button')), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_privacy_button')), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.byKey(const Key('doctor_profile_delete_account_button')), findsOneWidget);
      expect(find.text('Delete my account'), findsOneWidget);

      // Capture bottom screenshot (Screenshot 2 reference)
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir\\gs_health_doctor_profile_bottom.png',
      );
    });

    testWidgets('2. Interactive workflows: language chip toggling, edit profile modal, reviews modal, terms & logout', (tester) async {
      final service = PatientProblemService();

      final testDoctor = DoctorModel(
        id: 'doc-ananya-rao',
        userId: 'user-ananya-rao',
        name: 'Dr. Ananya Rao',
        specialty: 'Endodontist',
        qualification: 'BDS, MDS',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 38,
        clinicName: 'Bandra West Dental Clinic',
        phone: '+919000000001',
        email: 'ananya@gshealth.in',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['Today, 2:00 PM'],
        consultationFee: '₹800',
        languages: ['English', 'Hindi'],
      );

      service.currentDoctor = testDoctor;
      service.addTestDoctor(testDoctor);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: const DoctorProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // A. Toggle Language Chip (Tap Marathi)
      final marathiChip = find.byKey(const Key('doctor_language_chip_Marathi'));
      expect(marathiChip, findsOneWidget);
      await tester.tap(marathiChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.currentDoctor?.languages.contains('Marathi'), isTrue);

      // B. Open Edit Profile Modal
      final editBtn = find.byKey(const Key('doctor_profile_edit_button'));
      await tester.tap(editBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Edit Doctor Profile'), findsOneWidget);
      expect(find.byKey(const Key('save_doctor_profile_button')), findsOneWidget);

      // Save Changes
      await tester.tap(find.byKey(const Key('save_doctor_profile_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // C. Open Patient Reviews Modal
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final reviewsBtn = find.byKey(const Key('doctor_profile_reviews_button'));
      await tester.tap(reviewsBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Patient Reviews'), findsOneWidget);
      expect(find.text('Verified feedback from consulted patients'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);

      // Close Reviews Sheet
      expect(find.byKey(const Key('close_reviews_dialog_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close_reviews_dialog_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // D. Open Terms of Use Dialog
      final termsBtn = find.byKey(const Key('doctor_profile_terms_button'));
      await tester.scrollUntilVisible(termsBtn, 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(termsBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('terms_dialog_title')), findsOneWidget);
      expect(find.byKey(const Key('close_terms_dialog_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close_terms_dialog_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // E. Open Log Out Confirmation Dialog
      final logoutBtn = find.byKey(const Key('doctor_profile_logout_button'));
      await tester.scrollUntilVisible(logoutBtn, 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(logoutBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Log out?'), findsOneWidget);
      expect(find.byKey(const Key('cancel_logout_button')), findsOneWidget);
      expect(find.byKey(const Key('confirm_logout_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel_logout_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Log out?'), findsNothing);
    });

    testWidgets('3. Navigation from Doctor Dashboard Profile Icon to Doctor Profile Screen', (tester) async {
      final service = PatientProblemService();

      final testDoctor = DoctorModel(
        id: 'doc-ananya-rao',
        userId: 'user-ananya-rao',
        name: 'Dr. Ananya Rao',
        specialty: 'Endodontist',
        qualification: 'BDS, MDS',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 38,
        clinicName: 'Bandra West Dental Clinic',
        phone: '+919000000001',
        email: 'ananya@gshealth.in',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['Today, 2:00 PM'],
        consultationFee: '₹800',
        languages: ['English', 'Hindi', 'Telugu'],
      );

      service.currentDoctor = testDoctor;
      service.addTestDoctor(testDoctor);

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: const DentistTimelineScreen(initialTabIndex: 0),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap profile icon in Doctor Dashboard
      final profileIcon = find.byKey(const Key('dentist_profile_button'));
      expect(profileIcon, findsOneWidget);
      await tester.tap(profileIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Successfully pushed to DoctorProfileScreen
      expect(find.byType(DoctorProfileScreen), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.descendant(of: find.byType(DoctorProfileScreen), matching: find.text('Dr. Ananya Rao')), findsOneWidget);
      expect(find.text('LANGUAGES YOU CONSULT IN'), findsOneWidget);

      // Back navigation returns to DentistTimelineScreen
      final backBtn = find.byKey(const Key('doctor_profile_back_button'));
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DentistTimelineScreen), findsOneWidget);
    });

    testWidgets('4. Multi-viewport responsiveness across 320px, 360px, 390px, and 412px widths with zero RenderFlex overflows', (tester) async {
      final service = PatientProblemService();

      final testDoctor = DoctorModel(
        id: 'doc-ananya-rao',
        userId: 'user-ananya-rao',
        name: 'Dr. Ananya Rao',
        specialty: 'Endodontist',
        qualification: 'BDS, MDS (Endodontics)',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 38,
        clinicName: 'Bandra West Dental Clinic',
        phone: '+919000000001',
        email: 'ananya@gshealth.in',
        status: 'Available',
        verificationStatus: 'VERIFIED',
        nextAvailableSlots: ['Today, 2:00 PM'],
        consultationFee: '₹800',
        languages: ['English', 'Hindi', 'Telugu', 'Marathi', 'Tamil'],
      );

      service.currentDoctor = testDoctor;
      service.addTestDoctor(testDoctor);

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 892);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: const Scaffold(
                backgroundColor: Color(0xFFF8FAFC),
                body: DoctorProfileScreen(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('Dr. Ananya Rao'), findsOneWidget);
        expect(find.text('LANGUAGES YOU CONSULT IN'), findsOneWidget);

        // Scroll down
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Log out'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Zero RenderFlex overflows at ${width}px');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
