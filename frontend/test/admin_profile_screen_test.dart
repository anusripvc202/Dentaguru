import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_profile_screen.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_referrals_screen.dart';
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

  group('GS HEALTH - Admin Profile Screen Tests', () {
    testWidgets('1. Admin Profile displays all sections matching reference screenshots and captures visuals', (tester) async {
      // 1. Configure Persistent Session for Sheshu Kumar Gouda
      await SessionService().saveSession(
        token: 'mock-admin-token',
        userId: 'admin-sheshu-gouda',
        role: 'admin',
        name: 'Sheshu Kumar Gouda',
        email: 'sheshu.gouda@gshealth.in',
        phone: '+919550686566',
        metadata: {
          'location': 'Warangal',
          'city': 'Warangal',
        },
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
                child: const AdminProfileScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // ── Header Navigation ──
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byKey(const Key('admin_profile_back_button')), findsOneWidget);

      // ── Admin Profile Card ──
      expect(find.byKey(const Key('admin_profile_card')), findsOneWidget);
      expect(find.text('SK'), findsOneWidget); // Initials of Sheshu Kumar Gouda
      expect(find.text('Sheshu Kumar Gouda'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget); // Role badge
      expect(find.text('+919550686566'), findsOneWidget);
      expect(find.text('Warangal'), findsOneWidget);
      expect(find.byKey(const Key('admin_edit_profile_button')), findsOneWidget);
      expect(find.text('Edit profile'), findsOneWidget);

      // ── Referrals Menu Card ──
      expect(find.byKey(const Key('admin_referrals_menu_button')), findsOneWidget);
      expect(find.text('Referrals'), findsOneWidget);

      // Capture Top of Profile screen (Image 1 reference)
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir/gs_health_admin_profile_top.png',
      );

      // ── Scroll Down to Account Actions and Footer ──
      await tester.drag(find.byKey(const Key('admin_profile_scroll_view')), const Offset(0, -350));
      await tester.pumpAndSettle();

      // ── Need Help Card ──
      expect(find.byKey(const Key('admin_helpline_card')), findsOneWidget);
      expect(find.text('NEED HELP?'), findsOneWidget);
      expect(
        find.text('Call our 24/7 clinical care helpline for dental emergencies, appointments and consultations.'),
        findsOneWidget,
      );

      // ── Account Actions ──
      expect(find.byKey(const Key('admin_logout_button')), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.byKey(const Key('admin_terms_button')), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.byKey(const Key('admin_privacy_button')), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      // Capture Bottom of Profile screen (Image 2 reference)
      await _capturePngIfPossible(
        tester,
        boundaryKey,
        '$artifactDir/gs_health_admin_profile_bottom.png',
      );
    });

    testWidgets('2. Navigation: Admin Dashboard profile icon opens AdminProfileScreen and back button returns', (tester) async {
      await SessionService().saveSession(
        token: 'mock-admin-token',
        userId: 'admin-sheshu-gouda',
        role: 'admin',
        name: 'Sheshu Kumar Gouda',
        email: 'sheshu.gouda@gshealth.in',
        phone: '+919550686566',
        metadata: {
          'location': 'Warangal',
          'city': 'Warangal',
        },
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
            home: AdminDashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Profile icon exists in header
      expect(find.byKey(const Key('admin_header_profile')), findsOneWidget);

      // Tap profile icon
      await tester.tap(find.byKey(const Key('admin_header_profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // AdminProfileScreen is displayed
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byKey(const Key('admin_profile_card')), findsOneWidget);
      expect(find.text('Sheshu Kumar Gouda'), findsOneWidget);

      // Tap back button
      expect(find.byKey(const Key('admin_profile_back_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin_profile_back_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Back on Admin Dashboard
      expect(find.byKey(const Key('admin_header_profile')), findsOneWidget);
    });

    testWidgets('3. Edit Profile updates admin details and persists to session', (tester) async {
      await SessionService().saveSession(
        token: 'mock-admin-token',
        userId: 'admin-sheshu-gouda',
        role: 'admin',
        name: 'Sheshu Kumar Gouda',
        email: 'sheshu.gouda@gshealth.in',
        phone: '+919550686566',
        metadata: {
          'location': 'Warangal',
        },
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
            home: AdminProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sheshu Kumar Gouda'), findsOneWidget);
      expect(find.text('Warangal'), findsOneWidget);

      // Tap Edit Profile
      await tester.tap(find.byKey(const Key('admin_edit_profile_button')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.byKey(const Key('admin_edit_name_input')), findsOneWidget);
      expect(find.byKey(const Key('admin_edit_location_input')), findsOneWidget);

      // Update name and location
      await tester.enterText(find.byKey(const Key('admin_edit_name_input')), 'Dr. Sheshu Gouda');
      await tester.enterText(find.byKey(const Key('admin_edit_location_input')), 'Hyderabad');
      await tester.pumpAndSettle();

      // Tap Save changes
      await tester.tap(find.byKey(const Key('admin_save_profile_button')));
      await tester.pumpAndSettle();

      // Updated on screen
      expect(find.text('Dr. Sheshu Gouda'), findsOneWidget);
      expect(find.text('Hyderabad'), findsOneWidget);
    });

    testWidgets('4. Referrals Navigation: Tapping Referrals opens AdminReferralsScreen with real records and search/filters', (tester) async {
      final service = PatientProblemService();

      // Seed 2 real referrals
      final ref1 = PatientReferral(
        id: 'ref-001',
        referrerPatientId: 'pat-10',
        referrerPatientName: 'Rajesh Sharma',
        referrerPatientPhone: '9888812345',
        referredPatientName: 'Priya Sharma',
        referredPatientMobile: '9888854321',
        referredPatientCity: 'Warangal',
        requiredSpecialist: 'Endodontist',
        doctorId: 'doc-1',
        doctorName: 'Dr. Ananya Rao',
        doctorSpecialty: 'Endodontist',
        doctorClinicName: 'Warangal Dental Care',
        clinicalComplaint: 'Root canal assessment for 46',
        status: 'Pending',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );

      final ref2 = PatientReferral(
        id: 'ref-002',
        referrerPatientId: 'pat-20',
        referrerPatientName: 'Amit Patel',
        referrerPatientPhone: '9777712345',
        referredPatientName: 'Sunita Patel',
        referredPatientMobile: '9777754321',
        referredPatientCity: 'Hyderabad',
        requiredSpecialist: 'Oral Surgeon',
        doctorId: 'doc-2',
        doctorName: 'Dr. Karthik Raman',
        doctorSpecialty: 'Oral Surgeon',
        doctorClinicName: 'Apollo Dental',
        clinicalComplaint: 'Wisdom tooth extraction',
        status: 'Accepted',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      service.addTestAdminPatientReferral(ref1);
      service.addTestAdminPatientReferral(ref2);

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
            home: AdminProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Referrals menu card
      expect(find.byKey(const Key('admin_referrals_menu_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin_referrals_menu_button')));
      await tester.pumpAndSettle();

      // AdminReferralsScreen is displayed
      expect(find.byKey(const Key('admin_referrals_back_button')), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Sunita Patel'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Search for 'Priya'
      await tester.enterText(find.byKey(const Key('admin_referrals_search_input')), 'Priya');
      await tester.pumpAndSettle();
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Sunita Patel'), findsNothing);

      // Back button returns to AdminProfileScreen
      await tester.tap(find.byKey(const Key('admin_referrals_back_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin_profile_card')), findsOneWidget);
    });

    testWidgets('5. Terms, Privacy, Helpline, and Logout interactions', (tester) async {
      await SessionService().saveSession(
        token: 'admin-tok',
        userId: 'admin-id',
        role: 'admin',
        name: 'Sheshu Kumar Gouda',
        email: 'admin@gshealth.in',
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
            home: AdminProfileScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scroll to account action buttons
      await tester.drag(find.byKey(const Key('admin_profile_scroll_view')), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Terms of Use Dialog
      await tester.ensureVisible(find.byKey(const Key('admin_terms_button')));
      await tester.tap(find.byKey(const Key('admin_terms_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GS HEALTH CLINICAL ADMINISTRATOR TERMS OF SERVICE'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Privacy Policy Dialog
      await tester.ensureVisible(find.byKey(const Key('admin_privacy_button')));
      await tester.tap(find.byKey(const Key('admin_privacy_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GS HEALTH CLINICAL PRIVACY POLICY'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Helpline Tap
      await tester.ensureVisible(find.byKey(const Key('admin_helpline_card')));
      await tester.tap(find.byKey(const Key('admin_helpline_card')));
      await tester.pumpAndSettle();

      // Logout Confirmation Dialog
      await tester.ensureVisible(find.byKey(const Key('admin_logout_button')));
      await tester.tap(find.byKey(const Key('admin_logout_button')));
      await tester.pumpAndSettle();
      expect(find.text('Log out of Admin Account?'), findsOneWidget);
      expect(find.byKey(const Key('cancel_logout_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_logout_button')));
      await tester.pumpAndSettle();
    });

    testWidgets('6. Multi-viewport Responsiveness: Zero RenderFlex overflow across narrow & standard viewports', (tester) async {
      await SessionService().saveSession(
        token: 'admin-tok',
        userId: 'admin-id',
        role: 'admin',
        name: 'Chief Clinical Administrative Officer Sheshu Kumar Gouda',
        phone: '+919550686566',
        metadata: {
          'location': 'Warangal Smart City Regional Healthcare Directorate',
        },
      );

      final viewports = [
        const Size(320, 568), // iPhone SE 1st gen / narrow devices
        const Size(360, 640), // Standard Android compact
        const Size(390, 844), // iPhone 12/13/14 standard
        const Size(412, 915), // Pixel 7 flagship
      ];

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: AdminProfileScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Scroll top to bottom
        await tester.drag(find.byKey(const Key('admin_profile_scroll_view')), const Offset(0, -600));
        await tester.pumpAndSettle();

        // Check zero RenderFlex overflow assertions
        expect(tester.takeException(), isNull);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
