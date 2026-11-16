import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/theme/app_theme.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
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
// GS HEALTH – Clinic Registration (single continuous page) tests
// ---------------------------------------------------------------------------

final List<Map<String, dynamic>> _clinicPayloads = [];
int _clinicRegisterCalls = 0;
Map<String, dynamic>? get _firstClinicPayload =>
    _clinicPayloads.isNotEmpty ? _clinicPayloads.first : null;

void _installClinicRegisterOverride() {
  _clinicPayloads.clear();
  _clinicRegisterCalls = 0;
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
    String? clinicName,
    String? clinicAddress,
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
    _clinicRegisterCalls++;
    final payload = {
      'name': name,
      'phone': phone,
      'role': role,
      'clinicName': clinicName,
      'clinicAddress': clinicAddress,
      'city': city,
      'pincode': pincode,
    };
    _clinicPayloads.add(payload);
    return {
      'success': true,
      'token': 'clinic-reg-jwt',
      'user': {
        'id': 'cln-new-1',
        'name': name,
        'phone': phone,
        'role': role,
        'clinicName': clinicName,
      },
    };
  };
}

Future<void> _pumpClinicRegistration(
  WidgetTester tester, {
  GlobalKey? boundaryKey,
  Key? screenKey,
  String verifiedPhone = '9165438229',
}) async {
  final router = _buildAuthRouter(
    boundaryKey: boundaryKey,
    homeWidget: AuthScreen(
      key: screenKey,
      initialTab: 0,
      initialRole: 'clinic',
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
    'C1. Clinic registration renders GS HEALTH single page in reference order and captures top & bottom PNGs',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final boundaryKey = GlobalKey();
      await _pumpClinicRegistration(tester, boundaryKey: boundaryKey);

      // Branding
      expect(find.textContaining('DentaGuru'), findsNothing);
      expect(find.byKey(const Key('reg_gs_health_logo')), findsOneWidget);
      expect(find.text('Signed in as +919165438229'), findsOneWidget);
      expect(find.text('Welcome to\nGS HEALTH'), findsOneWidget);

      // 3-role grid with Clinic form active (Admin removed from public registration)
      for (final r in ['patient', 'dentist', 'clinic']) {
        expect(find.byKey(Key('reg_role_$r')), findsOneWidget);
      }
      expect(find.byKey(const Key('reg_role_admin')), findsNothing);
      expect(find.byKey(const ValueKey('clinic_form_section')), findsOneWidget);

      // Exact labels from the reference screenshots
      for (final label in [
        'FULL NAME',
        'CITY',
        'CLINIC / HOSPITAL NAME',
        'CLINIC ADDRESS',
        'PINCODE',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // Exact placeholders from reference screenshots
      expect(find.text('e.g. Riya Sharma'), findsOneWidget);
      expect(find.text('e.g. Mumbai'), findsOneWidget);
      expect(find.text('e.g. Smile Studio'), findsOneWidget);
      expect(find.text('Street, area'), findsOneWidget);
      expect(find.text('e.g. 400050'), findsOneWidget);

      // Vertical order matches reference
      double y(Key k) => tester.getTopLeft(find.byKey(k)).dy;
      final order = <Key>[
        const Key('reg_full_name_field'),
        const Key('reg_city_field'),
        const Key('reg_clinic_name_field'),
        const Key('reg_clinic_address_field'),
        const Key('reg_pincode_field'),
        const Key('reg_continue_button'),
        const Key('reg_use_another_number_button'),
      ];
      for (int i = 1; i < order.length; i++) {
        expect(y(order[i - 1]), lessThan(y(order[i])),
            reason: '${order[i - 1]} before ${order[i]}');
      }

      // OTP card hidden once mobile verified
      expect(find.byKey(const Key('reg_mobile_otp_card')), findsNothing);
      expect(tester.takeException(), isNull);

      await _capturePng(tester, boundaryKey, 'gs_health_clinic_registration_top.png');

      // Scroll down to bottom position and capture bottom screenshot
      await tester.drag(
        find.byKey(const Key('registration_scroll_view')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clinic_form_section')), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Use another number'), findsOneWidget);

      await _capturePng(tester, boundaryKey, 'gs_health_clinic_registration_bottom.png');
    },
  );

  testWidgets(
    'C2. Clinic Continue validates required fields and submits clinic registration via existing API',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _installClinicRegisterOverride();

      await _pumpClinicRegistration(tester);

      final continueFinder = find.byKey(const Key('reg_continue_button'));

      // 1. Empty Form -> Validation errors
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();
      expect(find.text('Please enter your name'), findsOneWidget);
      expect(find.text('Please enter clinic name'), findsOneWidget);
      expect(_clinicRegisterCalls, 0);

      // 2. Fill Name & Clinic Name, City empty -> City is mandatory
      await tester.enterText(
        find.byKey(const Key('reg_full_name_field')),
        'Riya Sharma',
      );
      await tester.enterText(
        find.byKey(const Key('reg_clinic_name_field')),
        'Smile Studio',
      );
      await tester.enterText(
        find.byKey(const Key('reg_city_field')),
        '',
      );
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();
      expect(find.text('⚠️ City is a mandatory field.'), findsOneWidget);
      expect(_clinicRegisterCalls, 0);

      // 3. Fill invalid 5-digit Pincode -> 6-digit PIN error
      await tester.enterText(
        find.byKey(const Key('reg_city_field')),
        'Mumbai',
      );
      await tester.enterText(
        find.byKey(const Key('reg_pincode_field')),
        '40005',
      );
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();
      expect(find.text('6-digit PIN'), findsOneWidget);
      expect(_clinicRegisterCalls, 0);

      // 4. Fill valid details & submit
      await tester.enterText(
        find.byKey(const Key('reg_clinic_address_field')),
        'Hill Road, Bandra West',
      );
      await tester.enterText(
        find.byKey(const Key('reg_pincode_field')),
        '400050',
      );
      await tester.ensureVisible(continueFinder);
      await tester.pumpAndSettle();
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(_clinicRegisterCalls, greaterThanOrEqualTo(1));
      expect(_firstClinicPayload?['role'], 'Clinic');
      expect(_firstClinicPayload?['name'], 'Riya Sharma');
      expect(_firstClinicPayload?['clinicName'], 'Smile Studio');
      expect(_firstClinicPayload?['clinicAddress'], 'Hill Road, Bandra West');
      expect(_firstClinicPayload?['city'], 'Mumbai');
      expect(_firstClinicPayload?['pincode'], '400050');
      expect(find.text('CLINIC_ROUTE'), findsOneWidget);
    },
  );

  testWidgets(
    'C3. Clinic page has zero overflow at 320/360/390/412 widths, inputs fit screen, keyboard keeps active input visible',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      addTearDown(tester.view.reset);

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 780);
        tester.view.devicePixelRatio = 1.0;

        await _pumpClinicRegistration(
          tester,
          screenKey: Key('clinic_reg_width_$width'),
        );
        expect(tester.takeException(), isNull,
            reason: 'No overflow at width $width');

        // Inputs and buttons fit within screen width
        for (final k in [
          const Key('reg_full_name_field'),
          const Key('reg_city_field'),
          const Key('reg_clinic_name_field'),
          const Key('reg_clinic_address_field'),
          const Key('reg_pincode_field'),
          const Key('reg_continue_button'),
          const Key('reg_use_another_number_button'),
        ]) {
          await tester.ensureVisible(find.byKey(k));
          await tester.pumpAndSettle();
          final r = tester.getRect(find.byKey(k));
          expect(r.left, greaterThanOrEqualTo(0), reason: '$k left at $width');
          expect(r.right, lessThanOrEqualTo(width),
              reason: '$k right at $width');
        }
        expect(tester.takeException(), isNull,
            reason: 'No overflow at width $width');
        await PatientProblemService().clearAllData();
      }

      // Keyboard open simulation on narrow layout
      tester.view.physicalSize = const Size(360, 760);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await _pumpClinicRegistration(
        tester,
        screenKey: const Key('clinic_reg_keyboard'),
      );

      final pincodeField = find.byKey(const Key('reg_pincode_field'));
      await tester.ensureVisible(pincodeField);
      await tester.pumpAndSettle();
      await tester.tap(pincodeField);
      await tester.pumpAndSettle();
      final fieldRect = tester.getRect(pincodeField);
      expect(fieldRect.bottom, lessThanOrEqualTo(760 - 320 + 0.5),
          reason: 'Active input must stay above keyboard');

      await tester.ensureVisible(find.byKey(const Key('reg_continue_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reg_continue_button')), findsOneWidget);
    },
  );
}
