import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/features/auth/presentation/widgets/gs_health_registration_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kArtifactsDir =
    r'C:\Users\ADMIN\.gemini\antigravity\brain\0cdf62c7-364d-4c39-8424-4bae41245b5b';

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

      for (final family in [
        'Roboto',
        'Plus Jakarta Sans',
        'Outfit',
        'Segoe UI',
      ]) {
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

void _installGoogleFontsAssetHandler(WidgetTester tester) {
  final regFile = File(r'C:\Windows\Fonts\segoeui.ttf');
  final boldFile = File(r'C:\Windows\Fonts\segoeuib.ttf');
  final regBytes = regFile.existsSync() ? regFile.readAsBytesSync() : Uint8List(0);
  final boldBytes =
      boldFile.existsSync() ? boldFile.readAsBytesSync() : regBytes;

  final manifestFile = File('build/unit_test_assets/AssetManifest.bin');
  final Map<Object?, Object?> manifestMap = <Object?, Object?>{};
  if (manifestFile.existsSync()) {
    final decoded = const StandardMessageCodec().decodeMessage(
      ByteData.sublistView(manifestFile.readAsBytesSync()),
    );
    if (decoded is Map) {
      manifestMap.addAll(decoded.cast<Object?, Object?>());
    }
  }

  const fontAssets = <String>[
    'google_fonts/PlusJakartaSans-Regular.ttf',
    'google_fonts/PlusJakartaSans-Medium.ttf',
    'google_fonts/PlusJakartaSans-SemiBold.ttf',
    'google_fonts/PlusJakartaSans-Bold.ttf',
    'google_fonts/PlusJakartaSans-ExtraBold.ttf',
    'google_fonts/Outfit-Regular.ttf',
    'google_fonts/Outfit-Medium.ttf',
    'google_fonts/Outfit-SemiBold.ttf',
    'google_fonts/Outfit-Bold.ttf',
  ];
  for (final asset in fontAssets) {
    manifestMap[asset] = <Object?>[
      <Object?, Object?>{'asset': asset},
    ];
  }
  final encodedManifest = const StandardMessageCodec().encodeMessage(manifestMap);

  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      if (message == null) return null;
      final key = utf8.decode(message.buffer.asUint8List());
      if (key == 'AssetManifest.bin') {
        return encodedManifest;
      }
      if (key.startsWith('google_fonts/')) {
        final bytes =
            (key.contains('Bold') || key.contains('SemiBold'))
                ? boldBytes
                : regBytes;
        return ByteData.sublistView(bytes);
      }
      final builtFile = File('build/unit_test_assets/$key');
      if (builtFile.existsSync()) {
        return ByteData.sublistView(builtFile.readAsBytesSync());
      }
      final directFile = File(key);
      if (directFile.existsSync()) {
        return ByteData.sublistView(directFile.readAsBytesSync());
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });
}

Future<void> _capturePng(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  await tester.runAsync(() async {
    final imageFinder = find.descendant(
      of: find.byKey(boundaryKey),
      matching: find.byType(Image),
    );
    for (final element in imageFinder.evaluate()) {
      final img = element.widget as Image;
      await precacheImage(img.image, element);
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    try {
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final outFile = File('$_kArtifactsDir\\$filename');
      await outFile.writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {}
  });
}

GoRouter _buildAuthRouter({
  required Widget homeWidget,
  GlobalKey? boundaryKey,
}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => boundaryKey == null
            ? homeWidget
            : RepaintBoundary(key: boundaryKey, child: homeWidget),
      ),
      GoRoute(
        path: '/patient',
        builder: (_, __) => const Scaffold(body: Center(child: Text('PATIENT_ROUTE'))),
      ),
      GoRoute(
        path: '/dentist',
        builder: (_, __) => const Scaffold(body: Center(child: Text('DENTIST_ROUTE'))),
      ),
      GoRoute(
        path: '/clinic',
        builder: (_, __) => const Scaffold(body: Center(child: Text('CLINIC_ROUTE'))),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const Scaffold(body: Center(child: Text('ADMIN_ROUTE'))),
      ),
      GoRoute(
        path: '/sub-admin',
        builder: (_, __) => const Scaffold(body: Center(child: Text('SUB_ADMIN_ROUTE'))),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// GS HEALTH – Dentist Registration (single continuous page) tests
// ---------------------------------------------------------------------------

final List<Map<String, dynamic>> _dentistPayloads = [];
int _dentistRegisterCalls = 0;
Map<String, dynamic>? get _firstDentistPayload =>
    _dentistPayloads.isNotEmpty ? _dentistPayloads.first : null;

void _installDentistRegisterOverride() {
  _dentistPayloads.clear();
  _dentistRegisterCalls = 0;
  ApiService.debugRegisterOverride = ({
    required String name,
    required String phone,
    String? email,
    String? password,
    String role = 'Patient',
    String? age,
    String? gender,
    String? bloodGroup,
    String? emergencyContact,
    String? specialty,
    String? licenseNumber,
    String? clinicId,
    String? clinicName,
    String? clinicAddress,
    String? consultationFee,
    String? bio,
    String? location,
    String? state,
    String? city,
    String? pincode,
    double? latitude,
    double? longitude,
    String? qualification,
    int? experienceYears,
    String? profilePhoto,
    List<String>? languages,
    String? referralCode,
  }) async {
    _dentistRegisterCalls++;
    final payload = {
      'name': name,
      'phone': phone,
      'role': role,
      'specialty': specialty,
      'qualification': qualification,
      'experienceYears': experienceYears,
      'clinicName': clinicName,
      'clinicAddress': clinicAddress,
      'city': city,
      'languages': languages,
    };
    _dentistPayloads.add(payload);
    return {
      'success': true,
      'token': 'dentist-reg-jwt',
      'user': {
        'id': 'doc-new-1',
        'name': name,
        'phone': phone,
        'role': role,
      },
    };
  };
}

void _seedRegisteredClinic() {
  PatientProblemService().addTestClinic(
    ClinicModel(
      id: 'cln-anna-nagar',
      clinicName: 'Anna Nagar Dental Clinic',
      location: '2nd Avenue, Anna Nagar, Chennai',
    ),
  );
}

Future<void> _pumpDentistRegistration(
  WidgetTester tester, {
  GlobalKey? boundaryKey,
  Key? screenKey,
  String verifiedPhone = '8976543258',
}) async {
  final router = _buildAuthRouter(
    boundaryKey: boundaryKey,
    homeWidget: AuthScreen(
      key: screenKey,
      initialTab: 0,
      initialRole: 'dentist',
      initialVerifiedPhone: verifiedPhone,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugLoginOverride = null;
    ApiService.debugRegisterOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugLoginOverride = null;
    ApiService.debugRegisterOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  testWidgets(
    'D1. Dentist registration renders GS HEALTH single page in reference order and captures top & bottom PNGs',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _seedRegisteredClinic();

      final boundaryKey = GlobalKey();
      await _pumpDentistRegistration(tester, boundaryKey: boundaryKey);

      // Branding
      expect(find.textContaining('DentaGuru'), findsNothing);
      expect(find.byKey(const Key('reg_gs_health_logo')), findsOneWidget);
      expect(find.text('Signed in as +918976543258'), findsOneWidget);
      expect(find.text('Welcome to\nGS HEALTH'), findsOneWidget);

      // 3-role grid with Dentist form active (Admin removed from public registration)
      for (final r in ['patient', 'dentist', 'clinic']) {
        expect(find.byKey(Key('reg_role_$r')), findsOneWidget);
      }
      expect(find.byKey(const Key('reg_role_admin')), findsNothing);
      expect(find.byKey(const ValueKey('dentist_form_section')), findsOneWidget);

      // Exact labels from the reference
      for (final label in [
        'FULL NAME',
        'CITY',
        'LANGUAGES YOU CONSULT IN',
        'SPECIALITY',
        'QUALIFICATION',
        'YEARS OF PRACTICE',
        'CLINIC (OPTIONAL)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // Removed legacy fields are no longer shown on the Dentist form
      expect(find.text('MEDICAL SPECIALTY'), findsNothing);
      expect(find.byKey(const Key('reg_pincode_field')), findsNothing);

      // Placeholders
      expect(find.text('e.g. Riya Sharma'), findsOneWidget);
      expect(find.text('e.g. Mumbai'), findsOneWidget);
      expect(find.text('e.g. BDS, MDS'), findsOneWidget);
      expect(find.text('e.g. 6'), findsOneWidget);

      // Languages: all 12 multi-select chips
      for (final lang in kGsHealthLanguages) {
        expect(find.byKey(Key('reg_lang_chip_$lang')), findsOneWidget);
      }

      // Specialty chips (friendly labels) incl. other supported specialties
      expect(find.text('General Dentist'), findsOneWidget);
      expect(find.text('Orthodontist'), findsOneWidget);
      expect(find.text('Endodontist'), findsOneWidget);
      expect(find.byKey(const Key('reg_specialty_chip_Prosthodontics')), findsOneWidget);

      // Clinic chips: Independent + registered clinic
      expect(find.byKey(const Key('reg_clinic_chip_independent')), findsOneWidget);
      expect(find.text('Anna Nagar Dental Clinic'), findsOneWidget);

      // Review note
      expect(
        find.text('New doctor profiles are reviewed by GS HEALTH before they appear to patients.'),
        findsOneWidget,
      );

      // Vertical order matches the reference
      double y(Key k) => tester.getTopLeft(find.byKey(k)).dy;
      final order = <Key>[
        const Key('reg_full_name_field'),
        const Key('reg_city_field'),
        const Key('reg_languages_wrap'),
        const Key('reg_specialty_scroll'),
        const Key('reg_qualification_field'),
        const Key('reg_experience_field'),
        const Key('reg_clinic_scroll'),
        const Key('reg_dentist_review_note'),
        const Key('reg_continue_button'),
        const Key('reg_use_another_number_button'),
      ];
      for (int i = 1; i < order.length; i++) {
        expect(y(order[i - 1]), lessThan(y(order[i])), reason: '${order[i - 1]} before ${order[i]}');
      }

      // OTP card hidden once mobile verified
      expect(find.byKey(const Key('reg_mobile_otp_card')), findsNothing);
      expect(tester.takeException(), isNull);

      await _capturePng(tester, boundaryKey, 'gs_health_dentist_registration_top.png');

      // Same continuous page, scrolled to the bottom
      await tester.drag(
        find.byKey(const Key('registration_scroll_view')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dentist_form_section')), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Use another number'), findsOneWidget);

      await _capturePng(tester, boundaryKey, 'gs_health_dentist_registration_bottom.png');
    },
  );

  testWidgets(
    'D2. Dentist Continue validates required fields and submits languages, specialty, qualification, years and clinic via existing registration',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _seedRegisteredClinic();
      _installDentistRegisterOverride();

      await _pumpDentistRegistration(tester);

      final continueFinder = find.byKey(const Key('reg_continue_button'));

      // Required: Full name
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();
      expect(find.text('Please enter your name'), findsOneWidget);
      expect(_dentistRegisterCalls, 0);

      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Dr. Riya Sharma');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Chennai');

      // Multi-select languages
      await tester.ensureVisible(find.byKey(const Key('reg_lang_chip_Tamil')));
      await tester.tap(find.byKey(const Key('reg_lang_chip_Tamil')));
      await tester.pumpAndSettle();

      // Specialty chip suggests qualification
      await tester.ensureVisible(find.byKey(const Key('reg_specialty_chip_Orthodontics')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reg_specialty_chip_Orthodontics')));
      await tester.pumpAndSettle();
      final qualField = tester.widget<TextFormField>(find.byKey(const Key('reg_qualification_field')));
      expect(qualField.controller?.text, 'BDS, MDS');

      // Typed qualification is not overwritten by a later specialty change
      await tester.enterText(find.byKey(const Key('reg_qualification_field')), 'BDS, MDS (Ortho)');
      await tester.tap(find.byKey(const Key('reg_specialty_chip_Orthodontics')));
      await tester.pumpAndSettle();
      expect(qualField.controller?.text, 'BDS, MDS (Ortho)');

      // Years of practice range validation
      await tester.enterText(find.byKey(const Key('reg_experience_field')), '99');
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();
      expect(find.text('Enter valid years of practice (0-70)'), findsOneWidget);
      expect(_dentistRegisterCalls, 0);
      await tester.enterText(find.byKey(const Key('reg_experience_field')), '6');

      // Clinic association: select clinic, then Independent clears, then reselect
      final clinicChip = find.byKey(const Key('reg_clinic_chip_cln-anna-nagar'));
      await tester.ensureVisible(clinicChip);
      await tester.pumpAndSettle();
      await tester.tap(clinicChip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reg_clinic_chip_independent')));
      await tester.pumpAndSettle();
      await tester.tap(clinicChip);
      await tester.pumpAndSettle();

      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(_dentistRegisterCalls, greaterThanOrEqualTo(1));
      expect(_firstDentistPayload?['role'], 'Dentist');
      expect(_firstDentistPayload?['name'], 'Dr. Riya Sharma');
      expect(_firstDentistPayload?['phone'], contains('8976543258'));
      expect(_firstDentistPayload?['city'], 'Chennai');
      expect(_firstDentistPayload?['specialty'], 'Orthodontics');
      expect(_firstDentistPayload?['qualification'], 'BDS, MDS (Ortho)');
      expect(_firstDentistPayload?['experienceYears'], 6);
      expect(_firstDentistPayload?['clinicName'], 'Anna Nagar Dental Clinic');
      expect(_firstDentistPayload?['clinicAddress'], '2nd Avenue, Anna Nagar, Chennai');
      expect(_firstDentistPayload?['languages'], ['English', 'Tamil']);
      expect(find.text('DENTIST_ROUTE'), findsOneWidget);
    },
  );

  testWidgets(
    'D3. Independent dentist submits without clinic association',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _installDentistRegisterOverride();

      await _pumpDentistRegistration(tester);

      // Independent is selected by default; General Dentist is the default specialty
      expect(find.byKey(const Key('reg_clinic_chip_independent')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Dr. Amit Verma');
      await tester.enterText(find.byKey(const Key('reg_city_field')), 'Mumbai');

      final continueFinder = find.byKey(const Key('reg_continue_button'));
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(_dentistRegisterCalls, greaterThanOrEqualTo(1));
      expect(_firstDentistPayload?['specialty'], 'General Medicine');
      expect(_firstDentistPayload?['clinicName'], isNull);
      expect(_firstDentistPayload?['clinicAddress'], isNull);
      expect(find.text('DENTIST_ROUTE'), findsOneWidget);
    },
  );

  testWidgets(
    'D4. Dentist page has zero overflow at 320/360/390/412, specialty chips stay reachable, keyboard keeps active input visible',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      addTearDown(tester.view.reset);

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        _seedRegisteredClinic();
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1.0;

        await _pumpDentistRegistration(
          tester,
          screenKey: Key('dentist_reg_width_$width'),
        );
        expect(tester.takeException(), isNull, reason: 'No overflow at width $width');

        // Last specialty chip reachable by horizontal scroll and selectable
        final lastChip = find.byKey(const Key('reg_specialty_chip_Prosthodontics'));
        await tester.ensureVisible(lastChip);
        await tester.pumpAndSettle();
        final chipRect = tester.getRect(lastChip);
        expect(chipRect.right, lessThanOrEqualTo(width + 0.5), reason: 'chip reachable at $width');
        await tester.tap(lastChip);
        await tester.pumpAndSettle();

        // Inputs and buttons fit within the screen width
        for (final k in [
          const Key('reg_full_name_field'),
          const Key('reg_qualification_field'),
          const Key('reg_experience_field'),
          const Key('reg_continue_button'),
          const Key('reg_use_another_number_button'),
        ]) {
          await tester.ensureVisible(find.byKey(k));
          await tester.pumpAndSettle();
          final r = tester.getRect(find.byKey(k));
          expect(r.left, greaterThanOrEqualTo(0), reason: '$k left at $width');
          expect(r.right, lessThanOrEqualTo(width), reason: '$k right at $width');
        }

        // Language chips all within bounds (wrapped across rows, not clipped)
        for (final lang in kGsHealthLanguages) {
          final chip = find.byKey(Key('reg_lang_chip_$lang'));
          await tester.ensureVisible(chip);
          final r = tester.getRect(chip);
          expect(r.right, lessThanOrEqualTo(width), reason: '$lang chip at $width');
        }
        expect(tester.takeException(), isNull, reason: 'No overflow at width $width');
        await PatientProblemService().clearAllData();
      }

      // Keyboard open on narrow layout
      tester.view.physicalSize = const Size(360, 760);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await _pumpDentistRegistration(
        tester,
        screenKey: const Key('dentist_reg_keyboard'),
      );

      final expField = find.byKey(const Key('reg_experience_field'));
      await tester.ensureVisible(expField);
      await tester.pumpAndSettle();
      await tester.tap(expField);
      await tester.pumpAndSettle();
      final fieldRect = tester.getRect(expField);
      expect(fieldRect.bottom, lessThanOrEqualTo(760 - 320 + 0.5),
          reason: 'Active input must stay above the keyboard');

      await tester.ensureVisible(find.byKey(const Key('reg_continue_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reg_continue_button')), findsOneWidget);
    },
  );
}
