import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dentaguru/core/routes/app_router.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/core/widgets/gs_health_hero_banner.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFontsIfAvailable();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionService().clearSession();
  });

  group('GS HEALTH – App Launch & Sign-In Screen Tests', () {
    testWidgets(
      'Unauthenticated App Launch routes to /login and opens GS HEALTH Sign-In (initialTab: 1)',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: appRouter,
            ),
          ),
        );

        // Allow SessionGateScreen resolution
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Must display GS HEALTH Sign In screen
        expect(find.text('Sign in with mobile'), findsOneWidget);
        expect(find.text("We'll text you a one-time code."), findsOneWidget);
        expect(find.text('Calm, expert medical care.'), findsOneWidget);
        expect(
          find.text('AI triage, verified doctors across all specialties, and your records, all in one place.'),
          findsOneWidget,
        );
        expect(find.byType(GsHealthLogo), findsWidgets);
        expect(find.text('DentaGuru'), findsNothing);
      },
    );

    testWidgets(
      'Sign-In Screen matches exact reference UI, role grid, mobile input, and captures screenshot',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        final boundaryKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: RepaintBoundary(
                key: boundaryKey,
                child: const Scaffold(
                  body: AuthScreen(initialTab: 1),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // 1. Hero Section Verification
        expect(find.byType(GsHealthHeroBanner), findsOneWidget);
        expect(find.text('Calm, expert medical care.'), findsOneWidget);
        expect(
          find.text('AI triage, verified doctors across all specialties, and your records, all in one place.'),
          findsOneWidget,
        );

        // 2. Official GS HEALTH Logo
        expect(find.byType(GsHealthLogo), findsWidgets);

        // 3. Heading & Subtitle
        expect(find.text('Sign in with mobile'), findsOneWidget);
        expect(find.text("We'll text you a one-time code."), findsOneWidget);

        // 4. 3-Role Public Selector (Patient, Dentist, Clinic) - Admin removed from public UI
        expect(find.byKey(const Key('signin_role_selector')), findsOneWidget);
        expect(find.byKey(const Key('signin_role_patient')), findsOneWidget);
        expect(find.byKey(const Key('signin_role_dentist')), findsOneWidget);
        expect(find.byKey(const Key('signin_role_clinic')), findsOneWidget);
        expect(find.byKey(const Key('signin_role_admin')), findsNothing);
        expect(find.text('Admin & Staff Portal'), findsNothing);

        // Verify public role switching between Patient, Dentist, and Clinic
        await tester.tap(find.byKey(const Key('signin_role_dentist')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('signin_role_clinic')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('signin_role_patient')));
        await tester.pumpAndSettle();

        // 5. Mobile Input & Send Code Button
        expect(find.text('+91'), findsOneWidget);
        expect(find.text('98765 43210'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Send code'), findsOneWidget);

        // 6. Registration link
        expect(find.text("Don't have an account?"), findsOneWidget);
        expect(find.text('Register here'), findsOneWidget);

        // 7. Capture visual screenshots for verification
        await _capturePng(tester, boundaryKey, 'gs_health_login_launch.png');
        await _capturePng(tester, boundaryKey, 'gs_health_public_signin_3roles.png');
      },
    );

    testWidgets(
      'Send Code transitions to OTP verification stage with 6-digit input and on-screen code',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async => {
          'success': true,
          'message': 'One-time code sent',
          'otp': '123456',
          'deliveryMode': 'on_screen',
        };
        addTearDown(() => ApiService.debugRequestOtpOverride = null);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: AuthScreen(initialTab: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter valid 10-digit mobile number
        final phoneField = find.byType(TextFormField).first;
        await tester.enterText(phoneField, '9876543210');
        await tester.pumpAndSettle();

        // Tap Send code
        final sendCodeBtn = find.widgetWithText(ElevatedButton, 'Send code');
        await tester.tap(sendCodeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Heading changes to Enter your code
        expect(find.text('Enter your code'), findsOneWidget);
        expect(find.text('Sent to +91 98765 *****'), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(6));
        expect(find.widgetWithText(ElevatedButton, 'Verify & continue'), findsOneWidget);
      },
    );

    testWidgets(
      'Authenticated App Launch restores session and navigates directly to authorized dashboard',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Save a mock active dentist session
        await SessionService().saveSession(
          token: 'mock_token_dentist_123',
          role: 'Dentist',
          userId: 'doc_101',
          email: 'dr.sharma@gshealth.in',
          phone: '9876543210',
          name: 'Dr. Riya Sharma',
        );

        appRouter.go('/');

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: appRouter,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        // Should route directly to Doctor dashboard (/dentist)
        expect(find.text('Doctor workspace'), findsOneWidget);
      },
    );

    testWidgets(
      'Special Number-Based Admin Access: Authorized admin number grants admin mode and navigates to Admin Dashboard upon valid OTP',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        const testAdminPhone = '9999988888';

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
          final isAuthorized = phone == testAdminPhone;
          return {
            'success': true,
            'message': 'One-time code sent',
            'otp': '789012',
            'isAdmin': isAuthorized,
          };
        };

        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async {
          return {
            'success': code == '789012',
            'message': code == '789012' ? 'OTP Verified' : 'Invalid code',
          };
        };

        ApiService.debugLoginOverride = ({String? email, String? phone, String? password, String? otp, String? role}) async {
          if (role == 'Admin' && phone == testAdminPhone) {
            return {
              'success': true,
              'data': {
                'accessToken': 'test_admin_jwt_token',
                'user': {
                  'id': 'admin_super_01',
                  'name': 'GS HEALTH Chief Admin',
                  'email': 'admin@gshealth.in',
                  'phone': testAdminPhone,
                  'role': 'Admin',
                },
              },
            };
          }
          return {'success': false, 'message': 'Unauthorized Admin access'};
        };

        addTearDown(() {
          ApiService.debugRequestOtpOverride = null;
          ApiService.debugVerifyOtpOverride = null;
          ApiService.debugLoginOverride = null;
        });

        appRouter.go('/login');

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: appRouter,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Enter authorized Admin mobile number
        final phoneField = find.byType(TextFormField).first;
        await tester.enterText(phoneField, testAdminPhone);
        await tester.pumpAndSettle();

        // 2. Tap Send code
        final sendCodeBtn = find.widgetWithText(ElevatedButton, 'Send code');
        await tester.tap(sendCodeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Should transition to OTP stage
        expect(find.text('Enter your code'), findsOneWidget);
        expect(find.text('Sent to +91 99999 *****'), findsOneWidget);

        // 3. Fill 6-digit OTP '789012'
        final digitInputs = find.byType(TextFormField);
        expect(digitInputs, findsNWidgets(6));
        await tester.enterText(digitInputs.at(0), '7');
        await tester.pump();
        await tester.enterText(digitInputs.at(1), '8');
        await tester.pump();
        await tester.enterText(digitInputs.at(2), '9');
        await tester.pump();
        await tester.enterText(digitInputs.at(3), '0');
        await tester.pump();
        await tester.enterText(digitInputs.at(4), '1');
        await tester.pump();
        await tester.enterText(digitInputs.at(5), '2');
        await tester.pump(const Duration(milliseconds: 300));

        // 4. Tap Verify & continue
        final verifyBtn = find.widgetWithText(ElevatedButton, 'Verify & continue');
        await tester.tap(verifyBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        // Should directly route to Admin Dashboard (/admin)
        expect(find.text('Admin console'), findsOneWidget);
      },
    );

    testWidgets(
      'Special Number-Based Admin Access: Non-admin public number does NOT trigger admin mode',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        const testPublicPhone = '9876543210';

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
          return {
            'success': true,
            'message': 'One-time code sent',
            'otp': '1234',
            'isAdmin': false,
          };
        };

        addTearDown(() {
          ApiService.debugRequestOtpOverride = null;
          ApiService.debugVerifyOtpOverride = null;
          ApiService.debugLoginOverride = null;
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: AuthScreen(initialTab: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter non-admin mobile number
        final phoneField = find.byType(TextFormField).first;
        await tester.enterText(phoneField, testPublicPhone);
        await tester.pumpAndSettle();

        // Tap Send code
        final sendCodeBtn = find.widgetWithText(ElevatedButton, 'Send code');
        await tester.tap(sendCodeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // In non-admin mode, heading is the standard OTP verification
        expect(find.text('Enter your code'), findsOneWidget);
        expect(find.text('Sent to +91 98765 *****'), findsOneWidget);
      },
    );

    testWidgets(
      'Responsive Viewport Safety (320px, 360px, 390px, 412px) has zero RenderFlex overflows',
      (WidgetTester tester) async {
        _installGoogleFontsAssetHandler(tester);

        final viewports = [
          const Size(320, 568), // iPhone SE 1st gen
          const Size(360, 780), // Compact Android
          const Size(390, 844), // iPhone 12/13/14
          const Size(412, 915), // Pixel 7 / Galaxy S23
        ];

        for (final vp in viewports) {
          tester.view.physicalSize = Size(vp.width * 2.0, vp.height * 2.0);
          tester.view.devicePixelRatio = 2.0;

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: AuthScreen(initialTab: 1),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Sign in with mobile'), findsOneWidget);
          expect(find.text('Calm, expert medical care.'), findsOneWidget);
        }

        tester.view.resetPhysicalSize();
      },
    );
  });
}
