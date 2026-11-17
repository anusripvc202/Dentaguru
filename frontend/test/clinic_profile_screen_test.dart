import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/models/medical_specialty_model.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_profile_screen.dart';
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
    await SessionService().clearSession();
  });

  group('GS HEALTH - Clinic Profile Screen Tests', () {
    testWidgets('1. Clinic Profile displays all sections matching reference screenshots and captures visuals', (tester) async {
      final service = PatientProblemService();

      // Configure Session for Bandra Clinic Manager
      await SessionService().saveSession(
        token: 'mock-clinic-token',
        userId: 'user-clinic-mgr-100',
        role: 'clinic',
        name: 'Bandra Clinic Manager',
        email: 'bandra.manager@gshealth.in',
        phone: '+919000000100',
        metadata: {
          'location': 'Mumbai',
          'clinicName': 'Bandra West Dental Clinic',
        },
      );

      final clinic = ClinicModel(
        id: 'clinic-bandra-west',
        userId: 'user-clinic-mgr-100',
        clinicName: 'Bandra West Dental Clinic',
        location: 'Hill Road, Bandra West',
        phone: '+919000000100',
        rating: 4.8,
        reviewsCount: 36,
        isFeatured: true,
        featuredPlan: 'Premium',
      );
      service.addTestClinic(clinic);
      service.setAuthenticatedClinicSession(
        id: clinic.id,
        clinicName: clinic.clinicName,
        location: clinic.location,
        phone: clinic.phone,
        isFeatured: true,
      );

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
                child: const ClinicProfileScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // ── Section 1: Navigation Header ──
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byKey(const Key('clinic_profile_back_button')), findsOneWidget);

      // ── Section 2: Clinic Manager Card ──
      expect(find.byKey(const Key('clinic_manager_profile_card')), findsOneWidget);
      expect(find.text('BC'), findsOneWidget); // Initials of Bandra Clinic Manager
      expect(find.text('Bandra Clinic Manager'), findsOneWidget);
      expect(find.text('Clinic'), findsOneWidget); // Role badge
      expect(find.text('+919000000100'), findsOneWidget);
      expect(find.text('Mumbai'), findsOneWidget);
      expect(find.byKey(const Key('clinic_edit_profile_button')), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);

      // ── Section 3: Clinic Details Card ──
      expect(find.byKey(const Key('clinic_facility_details_card')), findsOneWidget);
      expect(find.text('CLINIC'), findsOneWidget);
      expect(find.text('Bandra West Dental Clinic'), findsOneWidget);
      expect(find.text('Hill Road, Bandra West'), findsOneWidget);
      expect(find.byKey(const Key('clinic_featured_badge')), findsOneWidget);
      expect(find.text('FEATURED CLINIC'), findsOneWidget);
      expect(find.byKey(const Key('clinic_edit_details_button')), findsOneWidget);
      expect(find.text('Edit clinic details'), findsOneWidget);

      // ── Section 4: Patient Referrals Menu Card ──
      expect(find.byKey(const Key('clinic_patient_referrals_button')), findsOneWidget);
      expect(find.text('Patient referrals'), findsOneWidget);

      // Capture Top of Profile screen (Image 1 reference)
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir/gs_health_clinic_profile_top.png',
      );

      // ── Section 5: Need Help Card ──
      await tester.drag(find.byKey(const Key('clinic_profile_scroll_view')), const Offset(0, -350));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clinic_helpline_card')), findsOneWidget);
      expect(find.text('NEED HELP?'), findsOneWidget);
      expect(
        find.text('Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations.'),
        findsOneWidget,
      );

      // ── Section 6: Account Actions ──
      expect(find.byKey(const Key('clinic_logout_button')), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.byKey(const Key('clinic_terms_button')), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.byKey(const Key('clinic_privacy_button')), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.byKey(const Key('clinic_delete_account_button')), findsOneWidget);
      expect(find.text('Delete my account'), findsOneWidget);

      // Capture Bottom of Profile screen (Image 2 reference)
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir/gs_health_clinic_profile_bottom.png',
      );
    });

    testWidgets('2. Navigation: Clinic Dashboard profile button opens ClinicProfileScreen and back button returns', (tester) async {
      final service = PatientProblemService();

      await SessionService().saveSession(
        token: 'mock-clinic-token',
        userId: 'user-clinic-mgr-100',
        role: 'clinic',
        name: 'Bandra Clinic Manager',
        email: 'bandra.manager@gshealth.in',
        phone: '+919000000100',
        metadata: {
          'location': 'Mumbai',
          'clinicName': 'Bandra West Dental Clinic',
        },
      );

      final clinic = ClinicModel(
        id: 'clinic-bandra-west',
        userId: 'user-clinic-mgr-100',
        clinicName: 'Bandra West Dental Clinic',
        location: 'Hill Road, Bandra West',
        phone: '+919000000100',
        isFeatured: true,
      );
      service.addTestClinic(clinic);
      service.setAuthenticatedClinicSession(
        id: clinic.id,
        clinicName: clinic.clinicName,
      );

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ClinicDashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Clinic Dashboard is active
      expect(find.byKey(const Key('clinic_profile_button')), findsOneWidget);

      // Tap profile icon
      await tester.tap(find.byKey(const Key('clinic_profile_button')));
      await tester.pumpAndSettle();

      // ClinicProfileScreen is now displayed
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byKey(const Key('clinic_manager_profile_card')), findsOneWidget);
      expect(find.text('Bandra Clinic Manager'), findsOneWidget);

      // Tap Back button
      expect(find.byKey(const Key('clinic_profile_back_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('clinic_profile_back_button')));
      await tester.pumpAndSettle();

      // Back at Clinic Dashboard
      expect(find.byKey(const Key('clinic_profile_button')), findsOneWidget);
    });

    testWidgets('3. Featured badge is hidden when clinic is not featured', (tester) async {
      final service = PatientProblemService();

      await SessionService().saveSession(
        token: 'mock-token',
        userId: 'user-clinic-standard',
        role: 'clinic',
        name: 'Standard Clinic Manager',
        email: 'standard@gshealth.in',
        phone: '+919888877770',
      );

      final clinic = ClinicModel(
        id: 'clinic-standard',
        userId: 'user-clinic-standard',
        clinicName: 'Standard Dental Care',
        location: 'Andheri East',
        phone: '+919888877770',
        isFeatured: false,
      );
      service.addTestClinic(clinic);
      service.setAuthenticatedClinicSession(
        id: clinic.id,
        clinicName: clinic.clinicName,
        isFeatured: false,
      );

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ClinicProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Standard Dental Care'), findsOneWidget);
      // FEATURED CLINIC badge should NOT exist
      expect(find.byKey(const Key('clinic_featured_badge')), findsNothing);
      expect(find.text('FEATURED CLINIC'), findsNothing);
    });

    testWidgets('4. Edit Profile updates manager details and reflects on screen', (tester) async {
      final service = PatientProblemService();

      await SessionService().saveSession(
        token: 'mock-token',
        userId: 'user-clinic-mgr-1',
        role: 'clinic',
        name: 'Dr. Rahul Verma',
        email: 'manager@gshealth.in',
        phone: '+919000000101',
        metadata: {'location': 'Pune'},
      );

      final clinic = ClinicModel(
        id: 'clinic-1',
        userId: 'user-clinic-mgr-1',
        clinicName: 'Pune Dental Hospital',
        location: 'FC Road, Pune',
        phone: '+919000000101',
      );
      service.addTestClinic(clinic);
      service.setAuthenticatedClinicSession(
        id: clinic.id,
        clinicName: clinic.clinicName,
      );

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ClinicProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Dr. Rahul Verma'), findsOneWidget);

      // Tap Edit Profile
      await tester.tap(find.byKey(const Key('clinic_edit_profile_button')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.byKey(const Key('clinic_edit_name_input')), findsOneWidget);

      // Enter new name
      await tester.enterText(find.byKey(const Key('clinic_edit_name_input')), 'Dr. Amit Verma');
      await tester.pumpAndSettle();

      // Tap Save changes
      await tester.tap(find.byKey(const Key('clinic_save_profile_button')));
      await tester.pumpAndSettle();

      // Check updated on screen
      expect(find.text('Dr. Amit Verma'), findsOneWidget);
    });

    testWidgets('5. Terms, Privacy, Logout, and Delete Account dialog interactions', (tester) async {
      final service = PatientProblemService();

      await SessionService().saveSession(
        token: 'tok',
        userId: 'user-clinic-1',
        role: 'clinic',
        name: 'Clinic Admin',
        email: 'c@gs.in',
        phone: '+919000000000',
      );

      final clinic = ClinicModel(
        id: 'c1',
        userId: 'user-clinic-1',
        clinicName: 'City Dental Clinic',
        location: 'Connaught Place, Delhi',
        phone: '+919000000000',
      );
      service.addTestClinic(clinic);
      service.setAuthenticatedClinicSession(
        id: clinic.id,
        clinicName: clinic.clinicName,
      );

      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ClinicProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scroll down to action buttons
      await tester.drag(find.byKey(const Key('clinic_profile_scroll_view')), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Test Terms of Use dialog
      await tester.ensureVisible(find.byKey(const Key('clinic_terms_button')));
      await tester.tap(find.byKey(const Key('clinic_terms_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GS HEALTH CLINIC PARTNER TERMS OF SERVICE'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Test Privacy Policy dialog
      await tester.ensureVisible(find.byKey(const Key('clinic_privacy_button')));
      await tester.tap(find.byKey(const Key('clinic_privacy_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GS HEALTH CLINICAL PRIVACY POLICY'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Test Logout confirmation dialog
      await tester.ensureVisible(find.byKey(const Key('clinic_logout_button')));
      await tester.tap(find.byKey(const Key('clinic_logout_button')));
      await tester.pumpAndSettle();
      expect(find.text('Log out of Clinic Account?'), findsOneWidget);
      expect(find.byKey(const Key('cancel_logout_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_logout_button')));
      await tester.pumpAndSettle();

      // Test Delete Account confirmation dialog
      await tester.ensureVisible(find.byKey(const Key('clinic_delete_account_button')));
      await tester.tap(find.byKey(const Key('clinic_delete_account_button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete clinic account?'), findsOneWidget);
      expect(find.byKey(const Key('cancel_delete_clinic_account_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_delete_clinic_account_button')));
      await tester.pumpAndSettle();
    });

    testWidgets('6. Responsive Layout: Zero RenderFlex overflow across narrow & standard viewports', (tester) async {
      final service = PatientProblemService();

      final clinic = ClinicModel(
        id: 'clinic-resp',
        userId: 'user-resp',
        clinicName: 'Super Speciality Advanced Multi-Department Dental Hospital and Implant Centre',
        location: 'Opposite Metro Station, Near Central Market Road, Complex 4, Mumbai Suburban',
        phone: '+919999988888',
        isFeatured: true,
      );
      service.addTestClinic(clinic);
      service.setAuthenticatedClinicSession(
        id: clinic.id,
        clinicName: clinic.clinicName,
      );

      final viewports = [
        const Size(320, 568), // iPhone SE 1st gen / narrow small devices
        const Size(360, 640), // Standard Android compact
        const Size(390, 844), // iPhone 12/13/14/15 standard
        const Size(412, 915), // Pixel 7 / modern Android flagship
      ];

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: ClinicProfileScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Scroll from top to bottom
        await tester.drag(find.byKey(const Key('clinic_profile_scroll_view')), const Offset(0, -600));
        await tester.pumpAndSettle();

        // Check no RenderFlex overflow error is raised
        expect(tester.takeException(), isNull);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
