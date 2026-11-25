import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/screens/refer_a_friend_screen.dart';

Future<void> _loadRealFontsIfAvailable() async {
  try {
    final regularFile = File(r'C:\Windows\Fonts\segoeui.ttf');
    final boldFile = File(r'C:\Windows\Fonts\segoeuib.ttf');
    final semiboldFile = File(r'C:\Windows\Fonts\seguisb.ttf');
    if (regularFile.existsSync()) {
      final regBytes = regularFile.readAsBytesSync();
      final boldBytes =
          boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;
      final semiBytes =
          semiboldFile.existsSync() ? semiboldFile.readAsBytesSync() : boldBytes;

      for (final family in ['Roboto', 'Plus Jakarta Sans', 'Outfit']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.view(Uint8List.fromList(regBytes).buffer)),
          )
          ..addFont(
            Future.value(ByteData.view(Uint8List.fromList(semiBytes).buffer)),
          )
          ..addFont(
            Future.value(ByteData.view(Uint8List.fromList(boldBytes).buffer)),
          );
        await loader.load();
      }
    }

    final symbolFile = File(r'C:\Windows\Fonts\seguisym.ttf');
    if (symbolFile.existsSync()) {
      final symBytes = symbolFile.readAsBytesSync();
      final symLoader = FontLoader('Segoe UI Symbol')
        ..addFont(
          Future.value(ByteData.view(Uint8List.fromList(symBytes).buffer)),
        );
      await symLoader.load();
    }

    final envPath = Platform.environment['PATH'] ?? '';
    for (final dir in envPath.split(';')) {
      if (dir.toLowerCase().contains('flutter')) {
        final sdkRoot = Directory(dir).parent.path;
        final iconFontFile = File(
          '$sdkRoot\\bin\\cache\\artifacts\\material_fonts\\MaterialIcons-Regular.otf',
        );
        if (iconFontFile.existsSync()) {
          final iconBytes = iconFontFile.readAsBytesSync();
          final iconLoader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.view(Uint8List.fromList(iconBytes).buffer)),
            );
          await iconLoader.load();
          break;
        }
      }
    }
  } catch (_) {}
}

Future<void> _capturePngIfPossible(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String outputPath,
) async {
  await tester.runAsync(() async {
    try {
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File(outputPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {}
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const String artifactDir =
      r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await PatientProblemService().clearAllData();
  });

  void seedPatientProfileData(PatientProblemService service) {
    service.updatePatientProfile(
      id: 'pat-gs-profile-1',
      name: 'Ananya Verma',
      email: 'ananya.verma@gshealth.in',
      phone: '9848022338',
      age: '29',
      gender: 'Female',
      bloodGroup: 'O Positive (O+)',
      emergencyContact: '9848022338',
      city: 'Hyderabad',
      pincode: '500033',
      languages: const ['English', 'Hindi'],
    );
  }

  group('GS HEALTH Patient Profile & Health Locker Medical Terminology Tests', () {
    testWidgets(
      '1. Profile page renders one continuous vertical scroll with all 10 sections and captures top & bottom screenshots',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedPatientProfileData(service);

        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const PatientDashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Open Profile tab via top-right avatar button
        final avatarBtn = find.byKey(const Key('dashboard_profile_avatar_button'));
        expect(avatarBtn, findsOneWidget);
        await tester.tap(avatarBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Verify Profile Header
        expect(find.byKey(const Key('profile_back_button')), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);

        // 2. Verify Patient Profile Card (dynamic authenticated data, not hardcoded)
        expect(find.byKey(const Key('patient_profile_card')), findsOneWidget);
        expect(find.text('Ananya Verma'), findsOneWidget);
        expect(find.text('Patient'), findsOneWidget);
        expect(find.text('+919848022338'), findsOneWidget);
        expect(find.text('Hyderabad'), findsOneWidget);
        expect(find.byKey(const Key('edit_profile_button')), findsOneWidget);
        expect(find.text('Edit profile'), findsOneWidget);

        // 3. Verify Preferred Languages Card & all 12 language chips
        expect(find.byKey(const Key('preferred_languages_card')), findsOneWidget);
        expect(find.text('PREFERRED LANGUAGES'), findsOneWidget);
        const expectedLanguages = [
          'English',
          'Hindi',
          'Marathi',
          'Tamil',
          'Telugu',
          'Kannada',
          'Malayalam',
          'Bengali',
          'Gujarati',
          'Punjabi',
          'Urdu',
          'Odia',
        ];
        for (final lang in expectedLanguages) {
          expect(find.byKey(Key('profile_lang_chip_$lang')), findsOneWidget);
          expect(find.text(lang), findsOneWidget);
        }
        expect(
          find.text(
            'AI triage replies in your preferred language, and healthcare professionals who speak it are easy to find.',
          ),
          findsOneWidget,
        );

        // Capture Top Scroll Position Screenshot
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_profile_top.png',
        );

        // Scroll down the same continuous Profile scroll view to reveal lower sections
        final scrollView = find.byKey(const Key('profile_scroll_view'));
        expect(scrollView, findsOneWidget);
        await tester.drag(scrollView, const Offset(0, -560));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 4. Verify Referrals Card ("Referrals" and "Refer a friend")
        expect(find.byKey(const Key('profile_referrals_card')), findsOneWidget);
        expect(find.byKey(const Key('profile_referrals_row')), findsOneWidget);
        expect(find.text('Referrals'), findsOneWidget);
        expect(find.byKey(const Key('profile_refer_friend_row')), findsOneWidget);
        expect(find.text('Refer a friend'), findsOneWidget);

        // 5. Verify Need Help Card
        expect(find.byKey(const Key('profile_need_help_card')), findsOneWidget);
        expect(find.text('NEED HELP?'), findsOneWidget);
        expect(
          find.text(
            'Call our 24/7 clinical care helpline for medical emergencies, appointments and consultations.',
          ),
          findsOneWidget,
        );

        // 6. Verify Log Out Button
        expect(find.byKey(const Key('profile_logout_button')), findsOneWidget);
        expect(find.text('Log out'), findsOneWidget);

        // 7 & 8. Verify Terms of Use and Privacy Policy Buttons
        expect(find.byKey(const Key('profile_terms_button')), findsOneWidget);
        expect(find.text('Terms of Use'), findsOneWidget);
        expect(find.byKey(const Key('profile_privacy_button')), findsOneWidget);
        expect(find.text('Privacy Policy'), findsOneWidget);

        // 9. Verify Delete My Account Button
        expect(
          find.byKey(const Key('profile_delete_account_button')),
          findsOneWidget,
        );
        expect(find.text('Delete my account'), findsOneWidget);

        // 10. Verify Centered GS HEALTH Logo at bottom
        expect(
          find.byKey(const Key('profile_bottom_gs_health_logo')),
          findsOneWidget,
        );
        expect(find.byType(GsHealthLogo), findsOneWidget);

        // Capture Lower Scroll Position Screenshot
        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_profile_bottom.png',
        );
      },
    );

    testWidgets(
      '2. Multi-language selection toggles chips and persists preferred languages to service & SharedPreferences',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedPatientProfileData(service);
        service.currentPatient = PatientProfile(
          id: service.currentPatient.id,
          name: service.currentPatient.name,
          email: service.currentPatient.email,
          phone: service.currentPatient.phone,
          age: service.currentPatient.age,
          gender: service.currentPatient.gender,
          bloodGroup: service.currentPatient.bloodGroup,
          emergencyContact: service.currentPatient.emergencyContact,
          city: service.currentPatient.city,
          pincode: service.currentPatient.pincode,
          languages: service.currentPatient.languages,
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

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: const PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const Key('dashboard_profile_avatar_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Initially English and Hindi are selected
        expect(service.currentPatient.languages, containsAll(['English', 'Hindi']));

        // Select Telugu and Kannada as well
        await tester.tap(find.byKey(const Key('profile_lang_chip_Telugu')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('profile_lang_chip_Kannada')));
        await tester.pump();

        expect(
          service.currentPatient.languages,
          containsAll(['English', 'Hindi', 'Telugu', 'Kannada']),
        );

        // Deselect Hindi
        await tester.tap(find.byKey(const Key('profile_lang_chip_Hindi')));
        await tester.pump();

        expect(service.currentPatient.languages.contains('Hindi'), isFalse);
        expect(
          service.currentPatient.languages,
          containsAll(['English', 'Telugu', 'Kannada']),
        );

        // Verify persisted in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final savedProfileJson = prefs.getString('dentaguru_patient_profile');
        expect(savedProfileJson, isNotNull);
        final decoded = jsonDecode(savedProfileJson!) as Map<String, dynamic>;
        expect(
          List<String>.from(decoded['languages'] as List),
          containsAll(['English', 'Telugu', 'Kannada']),
        );
      },
    );

    testWidgets(
      '3. Edit profile modal saves updated patient name, mobile number, and city',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedPatientProfileData(service);
        service.currentPatient = PatientProfile(
          id: service.currentPatient.id,
          name: service.currentPatient.name,
          email: service.currentPatient.email,
          phone: service.currentPatient.phone,
          age: service.currentPatient.age,
          gender: service.currentPatient.gender,
          bloodGroup: service.currentPatient.bloodGroup,
          emergencyContact: service.currentPatient.emergencyContact,
          city: service.currentPatient.city,
          pincode: service.currentPatient.pincode,
          languages: service.currentPatient.languages,
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

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: const PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const Key('dashboard_profile_avatar_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Open Edit profile sheet
        await tester.tap(find.byKey(const Key('edit_profile_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Edit Profile'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('edit_profile_name_field')),
          'Kiran Reddy',
        );
        await tester.enterText(
          find.byKey(const Key('edit_profile_phone_field')),
          '9000112233',
        );
        await tester.enterText(
          find.byKey(const Key('edit_profile_city_field')),
          'Bengaluru',
        );

        await tester.tap(find.byKey(const Key('save_profile_changes_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify updated details appear on the Profile card and in service
        expect(find.text('Kiran Reddy'), findsOneWidget);
        expect(find.text('+919000112233'), findsOneWidget);
        expect(find.text('Bengaluru'), findsOneWidget);
        expect(service.currentPatient.name, 'Kiran Reddy');
        expect(service.currentPatient.city, 'Bengaluru');
      },
    );

    testWidgets(
      '4. Referrals, Refer a friend, Need Help, Terms, Privacy, Logout confirmation, and Delete Account confirmation work',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedPatientProfileData(service);
        service.currentPatient = PatientProfile(
          id: service.currentPatient.id,
          name: service.currentPatient.name,
          email: service.currentPatient.email,
          phone: service.currentPatient.phone,
          age: service.currentPatient.age,
          gender: service.currentPatient.gender,
          bloodGroup: service.currentPatient.bloodGroup,
          emergencyContact: service.currentPatient.emergencyContact,
          city: service.currentPatient.city,
          pincode: service.currentPatient.pincode,
          languages: service.currentPatient.languages,
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

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: const PatientDashboardScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const Key('dashboard_profile_avatar_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final scrollView = find.byKey(const Key('profile_scroll_view'));
        await tester.drag(scrollView, const Offset(0, -560));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // A. Need Help card opens helpline dialog
        await tester.tap(find.byKey(const Key('profile_need_help_card')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('GS HEALTH 24/7 Helpline'), findsOneWidget);
        expect(find.text('+91 95506 86566'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // B. Terms of Use dialog
        await tester.tap(find.byKey(const Key('profile_terms_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('Welcome to GS HEALTH'), findsOneWidget);
        await tester.tap(find.byKey(const Key('close_terms_dialog_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // C. Privacy Policy dialog
        await tester.tap(find.byKey(const Key('profile_privacy_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.textContaining('GS HEALTH Privacy Policy'), findsOneWidget);
        await tester.tap(find.byKey(const Key('close_privacy_dialog_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // D. Log out confirmation dialog
        await tester.tap(find.byKey(const Key('profile_logout_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Log out?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('cancel_logout_dialog_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // E. Delete my account confirmation dialog
        await tester.tap(find.byKey(const Key('profile_delete_account_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Delete my account?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('cancel_delete_account_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        // Account still intact after cancel
        expect(service.currentPatient.name, 'Ananya Verma');

        // F. Refer a friend row opens ReferAFriendScreen
        await tester.tap(find.byKey(const Key('profile_refer_friend_row')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ReferAFriendScreen), findsOneWidget);
      },
    );

    testWidgets(
      '5. Health Locker replaces "My teeth" with "Health Records" and captures updated screenshot',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        seedPatientProfileData(service);

        service.addMedicalRecord({
          'id': 'health-rec-1',
          'patientId': 'pat-gs-profile-1',
          'patientName': 'Ananya Verma',
          'type': 'clinical_document',
          'category': 'Clinical Document',
          'title': 'Comprehensive Clinical Evaluation & Dental Chart',
          'description': 'General health vitals, blood pressure normal, routine oral & systemic checkup.',
          'date': '2026-10-22',
          'fileName': 'clinical_evaluation.pdf',
          'fileType': 'PDF',
          'fileSize': 164000,
          'isPatientUpload': true,
        });
        service.currentPatient = PatientProfile(
          id: service.currentPatient.id,
          name: service.currentPatient.name,
          email: service.currentPatient.email,
          phone: service.currentPatient.phone,
          age: service.currentPatient.age,
          gender: service.currentPatient.gender,
          bloodGroup: service.currentPatient.bloodGroup,
          emergencyContact: service.currentPatient.emergencyContact,
          city: service.currentPatient.city,
          pincode: service.currentPatient.pincode,
          languages: service.currentPatient.languages,
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

        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
              home: RepaintBoundary(
                key: boundaryKey,
                child: const PatientDashboardScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Navigate to Locker tab
        final lockerNav = find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Locker'),
        );
        await tester.tap(lockerNav);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify updated medical terminology
        expect(find.text('Your medical & health records'), findsOneWidget);
        expect(find.text('Health locker'), findsOneWidget);
        expect(find.text('Health Records'), findsOneWidget);
        expect(find.text('My teeth'), findsNothing);

        // Tap "Health Records" tab
        await tester.tap(find.byKey(const Key('locker_tab_my_teeth')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Comprehensive Clinical Evaluation & Dental Chart'),
          findsOneWidget,
        );

        await _capturePngIfPossible(
          tester,
          boundaryKey,
          '$artifactDir\\gs_health_locker_health_records.png',
        );
      },
    );

    testWidgets(
      '6. Multi-viewport overflow check (320px, 360px, 390px, 412px) on Profile page',
      (tester) async {
        final service = PatientProblemService();
        seedPatientProfileData(service);

        const widths = [320.0, 360.0, 390.0, 412.0];
        for (final width in widths) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                key: ValueKey('profile_app_$width'),
                debugShowCheckedModeBanner: false,
                theme: ThemeData(fontFamily: 'Roboto', useMaterial3: false),
                home: PatientDashboardScreen(key: ValueKey('profile_dash_$width')),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          await tester.tap(find.byKey(const Key('dashboard_profile_avatar_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Profile top overflow at ${width}px',
          );

          final scrollView = find.byKey(const Key('profile_scroll_view'));
          await tester.drag(scrollView, const Offset(0, -560));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Profile bottom overflow at ${width}px',
          );
        }

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });
}
