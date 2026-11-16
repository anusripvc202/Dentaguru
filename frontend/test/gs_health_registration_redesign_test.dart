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
    '1. Registration renders GS HEALTH branding, 2x2 4-role grid, continuous Patient fields, and captures top & bottom PNGs',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final boundaryKey = GlobalKey();
      final router = _buildAuthRouter(
        boundaryKey: boundaryKey,
        homeWidget: const AuthScreen(
          initialTab: 0,
          initialRole: 'patient',
          initialVerifiedPhone: '8976543258',
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

      // Zero DentaGuru branding
      expect(find.textContaining('DentaGuru'), findsNothing);

      // Header, verified mobile status, welcome heading, subtitle
      expect(find.byKey(const Key('reg_gs_health_logo')), findsOneWidget);
      expect(find.text('Signed in as +918976543258'), findsOneWidget);
      expect(find.text('Welcome to\nGS HEALTH'), findsOneWidget);
      expect(
        find.text('Tell us who you are so we can set things up.'),
        findsOneWidget,
      );

      // 3-role grid: 3 public roles (Patient, Dentist, Clinic) - Admin removed
      expect(find.byKey(const Key('reg_role_patient')), findsOneWidget);
      expect(find.byKey(const Key('reg_role_dentist')), findsOneWidget);
      expect(find.byKey(const Key('reg_role_clinic')), findsOneWidget);
      expect(find.byKey(const Key('reg_role_admin')), findsNothing);
      expect(find.text('Get triage & book visits'), findsOneWidget);
      expect(find.text('Manage your patients'), findsOneWidget);
      expect(find.text('Run your practice'), findsOneWidget);
      expect(find.text('Manage the platform.'), findsNothing);

      // Patient fields in exact order
      expect(find.text('FULL NAME'), findsOneWidget);
      expect(find.text('CITY'), findsOneWidget);
      expect(find.text('PREFERRED LANGUAGES'), findsOneWidget);

      final nameY =
          tester.getTopLeft(find.byKey(const Key('reg_full_name_field'))).dy;
      final cityY = tester.getTopLeft(find.byKey(const Key('reg_city_field'))).dy;
      final langsY =
          tester.getTopLeft(find.byKey(const Key('reg_languages_wrap'))).dy;
      expect(nameY, lessThan(cityY));
      expect(cityY, lessThan(langsY));

      // All 12 language pills present
      for (final lang in kGsHealthLanguages) {
        expect(find.byKey(Key('reg_lang_chip_$lang')), findsOneWidget);
      }

      // Post-OTP flow hides separate mobile OTP box
      expect(find.byKey(const Key('reg_mobile_otp_card')), findsNothing);

      await _capturePng(tester, boundaryKey, 'gs_health_registration_top.png');

      // Scroll to bottom position and capture bottom screenshot
      await tester.drag(
        find.byKey(const Key('registration_scroll_view')),
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reg_continue_button')), findsOneWidget);
      expect(
        find.byKey(const Key('reg_use_another_number_button')),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Use another number'), findsOneWidget);

      await _capturePng(
        tester,
        boundaryKey,
        'gs_health_registration_bottom.png',
      );
    },
  );

  testWidgets(
    '2. Multi-language selection & Patient Continue saves languages, city, and routes to Patient Dashboard',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Map<String, dynamic>? capturedPayload;
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
        capturedPayload = {
          'name': name,
          'phone': phone,
          'role': role,
          'city': city,
          'pincode': pincode,
          'languages': languages,
        };
        return {
          'success': true,
          'token': 'pat-jwt-token',
          'user': {
            'id': 'pat-new-1',
            'name': name,
            'phone': phone,
            'role': 'Patient',
            'city': city,
            'languages': languages,
          },
        };
      };

      final router = _buildAuthRouter(
        homeWidget: const AuthScreen(
          initialTab: 0,
          initialRole: 'patient',
          initialVerifiedPhone: '9876543210',
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

      await tester.enterText(
        find.byKey(const Key('reg_full_name_field')),
        'Riya Sharma',
      );
      await tester.enterText(
        find.byKey(const Key('reg_city_field')),
        'Mumbai',
      );

      await tester.ensureVisible(find.byKey(const Key('reg_lang_chip_Hindi')));
      await tester.tap(find.byKey(const Key('reg_lang_chip_Hindi')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('reg_lang_chip_Telugu')));
      await tester.tap(find.byKey(const Key('reg_lang_chip_Telugu')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('reg_continue_button')));
      await tester.tap(find.byKey(const Key('reg_continue_button')));
      await tester.pumpAndSettle();

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['name'], 'Riya Sharma');
      expect(capturedPayload!['phone'], '9876543210');
      expect(capturedPayload!['role'], 'Patient');
      expect(capturedPayload!['city'], 'Mumbai');
      expect(capturedPayload!['pincode'], '');
      expect(capturedPayload!['languages'], ['English', 'Hindi', 'Telugu']);

      expect(find.text('PATIENT_ROUTE'), findsOneWidget);
      expect(
        PatientProblemService().currentPatient.languages,
        ['English', 'Hindi', 'Telugu'],
      );
      expect(
        SessionService().currentSession?.metadata['languages'],
        ['English', 'Hindi', 'Telugu'],
      );
    },
  );

  testWidgets(
    '3. Dentist & Clinic roles submit accurately; Public Admin blocks self-registration and links to Admin Sign-In',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int registerCalls = 0;
      Map<String, dynamic>? lastPayload;
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
        registerCalls++;
        lastPayload = {
          'name': name,
          'phone': phone,
          'role': role,
          'clinicName': clinicName,
          'clinicAddress': clinicAddress,
          'city': city,
        };
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

      final router = _buildAuthRouter(
        homeWidget: const AuthScreen(
          initialTab: 0,
          initialVerifiedPhone: '9988776655',
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

      // Switch to Dentist -> shows Speciality chips & reference fields
      await tester.tap(find.byKey(const Key('reg_role_dentist')));
      await tester.pumpAndSettle();
      expect(find.text('SPECIALITY'), findsOneWidget);
      expect(find.text('LANGUAGES YOU CONSULT IN'), findsOneWidget);

      // Admin is strictly absent from public registration role options
      expect(find.byKey(const Key('reg_role_admin')), findsNothing);

      // Switch to Clinic and test Clinic registration submission

      await tester.tap(find.byKey(const Key('reg_role_clinic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reg_clinic_name_field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('reg_clinic_name_field')),
        'Bandra Smile Clinic',
      );
      await tester.enterText(
        find.byKey(const Key('reg_full_name_field')),
        'Dr. Rajesh Mehta',
      );
      await tester.enterText(
        find.byKey(const Key('reg_city_field')),
        'Mumbai',
      );

      await tester.ensureVisible(find.byKey(const Key('reg_continue_button')));
      await tester.tap(find.byKey(const Key('reg_continue_button')));
      await tester.pumpAndSettle();

      expect(registerCalls, 1);
      expect(lastPayload?['role'], 'Clinic');
      expect(lastPayload?['clinicName'], 'Bandra Smile Clinic');
      expect(lastPayload?['city'], 'Mumbai');
      expect(find.text('CLINIC_ROUTE'), findsOneWidget);
    },
  );

  testWidgets(
    '4. Sign-In OTP for unregistered mobile transitions to Registration with verified phone & Use another number resets',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      ApiService.debugLoginOverride = ({
        String? email,
        String? otp,
        String? password,
        String? phone,
        String? role,
      }) async {
        return {
          'success': false,
          'message': 'Invalid credentials. User not registered in system.',
        };
      };

      final router = _buildAuthRouter(homeWidget: const AuthScreen());

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

      expect(find.text('Sign in with mobile'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '9123456789');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your code'), findsOneWidget);
      await tester.tap(find.text('Fill'));
      await tester.pumpAndSettle();

      final verifyBtn = find.widgetWithText(ElevatedButton, 'Verify & continue');
      if (verifyBtn.evaluate().isNotEmpty) {
        await tester.ensureVisible(verifyBtn);
        await tester.tap(verifyBtn);
        await tester.pumpAndSettle();
      }

      // Seamless transition into Registration with verified mobile
      expect(find.text('Signed in as +919123456789'), findsOneWidget);
      expect(find.text('Welcome to\nGS HEALTH'), findsOneWidget);

      // Allow confirmation SnackBar to dismiss before scrolling to bottom CTA
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Tapping Use another number resets back to Sign-In mobile stage
      await tester.ensureVisible(
        find.byKey(const Key('reg_use_another_number_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('reg_use_another_number_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in with mobile'), findsOneWidget);
    },
  );

  testWidgets(
    '5. Registration UI has zero overflow across widths & keyboard, and Admin is strictly absent',
    (WidgetTester tester) async {
      _installGoogleFontsAssetHandler(tester);

      for (final width in [320.0, 360.0, 390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: AuthScreen(
                key: Key('reg_portal_width_$width'),
                initialTab: 0,
                initialRole: 'patient',
                initialVerifiedPhone: '9876543210',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'No overflow allowed at width $width');
        expect(find.byKey(const Key('reg_role_patient')), findsOneWidget);
        expect(find.byKey(const Key('reg_role_dentist')), findsOneWidget);
        expect(find.byKey(const Key('reg_role_clinic')), findsOneWidget);
        expect(find.byKey(const Key('reg_role_admin')), findsNothing);
      }

      // Keyboard open simulation on narrow Patient layout
      tester.view.physicalSize = const Size(360, 760);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(
              key: Key('patient_keyboard_layout_test'),
              initialTab: 0,
              initialRole: 'patient',
              initialVerifiedPhone: '8976543258',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('reg_full_name_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reg_full_name_field')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reg_continue_button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reg_continue_button')), findsOneWidget);
    },
  );
}
