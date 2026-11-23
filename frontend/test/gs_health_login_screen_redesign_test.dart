import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/features/auth/presentation/screens/auth_screen.dart';
import 'package:dentaguru/core/constants/api_constants.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/widgets/denta_guru_logo.dart';
import 'package:dentaguru/core/widgets/gs_health_hero_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
      return {
        'success': true,
        'message': 'OTP sent successfully to your mobile number.',
        'isAdmin': false,
      };
    };
    ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async {
      return {
        'success': true,
        'message': 'OTP verified successfully.',
      };
    };
  });

  tearDown(() {
    ApiConstants.debugAllowOnScreenOtpOverride = null;
    ApiService.debugRequestOtpOverride = null;
    ApiService.debugVerifyOtpOverride = null;
    ApiService.debugLoginOverride = null;
  });

  group('GS HEALTH Premium Mobile Login & OTP Experience Tests', () {
    testWidgets('Renders Hero Section, GS HEALTH Branding, Mobile Input, and No Demo Buttons on Mobile Viewport', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400); // Standard mobile phone
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(), // Defaults to initialTab: 1 (Sign In)
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Hero Section Content Verification (Multi-Specialty Healthcare)
      expect(find.byType(GsHealthHeroBanner), findsOneWidget);
      expect(find.text('Calm, expert medical care.'), findsOneWidget);
      expect(
        find.text('AI triage, verified doctors across all specialties, and your records, all in one place.'),
        findsOneWidget,
      );

      // 2. Official GS HEALTH Branding in Card
      expect(find.byType(GsHealthLogo), findsWidgets);
      expect(find.text('DentaGuru'), findsNothing);

      // 3. Login Card Typography & Form Structure
      expect(find.text('Sign in with mobile'), findsOneWidget);
      expect(find.text("We'll text you a one-time code."), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      expect(find.text('98765 43210'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);

      // 4. Strict Production Requirement: Only 3 public roles (Patient, Dentist, Clinic) - Admin removed
      expect(find.text('DEMO ACCOUNTS · TAP TO FILL'), findsNothing);
      expect(find.byKey(const Key('signin_role_patient')), findsOneWidget);
      expect(find.byKey(const Key('signin_role_dentist')), findsOneWidget);
      expect(find.byKey(const Key('signin_role_clinic')), findsOneWidget);
      expect(find.byKey(const Key('signin_role_admin')), findsNothing);
      expect(find.text('Admin & Staff Portal'), findsNothing);
      expect(find.text('Doctor'), findsOneWidget);

      // Tapping Clinic role pill keeps OTP flow intact without overflow
      await tester.tap(find.byKey(const Key('signin_role_clinic')));
      await tester.pumpAndSettle();

      // 5. Terms & Privacy Policy Footer
      expect(find.text('By continuing you agree to our '), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('Entering valid mobile and tapping Send Code transitions to OTP stage with masked phone and Verify button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter valid 10-digit mobile number
      final phoneField = find.byType(TextFormField).first;
      await tester.enterText(phoneField, '9063663180');
      await tester.pumpAndSettle();

      // Tap Send code
      final sendCodeButton = find.widgetWithText(ElevatedButton, 'Send code');
      expect(sendCodeButton, findsOneWidget);
      await tester.tap(sendCodeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 1. Should now display OTP verification stage (Screenshot 2 Reference)
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.text('Sent to +91 90636 *****'), findsOneWidget);

      // 2. 6-digit OTP input boxes present
      expect(find.byType(TextFormField), findsNWidgets(6));

      // 3. Resend timer and edit mobile options present
      expect(find.text('← Edit mobile number'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);

      // 4. Action button text is "Verify & continue"
      expect(find.widgetWithText(ElevatedButton, 'Verify & continue'), findsOneWidget);
    });

    testWidgets('Debug testing mode displays on-screen 6-digit OTP banner and Fill button populates all 6 boxes', (WidgetTester tester) async {
      ApiConstants.debugAllowOnScreenOtpOverride = true;
      ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
        return {
          'success': true,
          'message': 'Verification code ready on screen (testing mode).',
          'otp': '482915',
          'deliveryMode': 'on_screen',
          'isAdmin': false,
        };
      };
      String? verifiedCode;
      ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async {
        verifiedCode = code;
        return {'success': code == '482915', 'message': 'OTP verified successfully.'};
      };
      String? loginOtpPassed;
      ApiService.debugLoginOverride = ({String? email, String? phone, String? password, String? otp, String? role}) async {
        loginOtpPassed = otp;
        return {'success': false, 'message': 'Invalid credentials. User not registered.'};
      };

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '9063663180');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('login_onscreen_otp_banner')), findsOneWidget);
      expect(find.text('Your verification code: 482915'), findsOneWidget);
      expect(find.byKey(const Key('login_otp_fill_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_otp_fill_button')));
      await tester.pumpAndSettle();

      expect(verifiedCode, '482915');
      expect(loginOtpPassed, isNull, reason: 'otpAlreadyVerified must prevent double OTP verification on login');
    });

    testWidgets('Production/release mode never displays on-screen OTP banner or code even if response contains otp', (WidgetTester tester) async {
      ApiConstants.debugAllowOnScreenOtpOverride = false;
      ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
        return {
          'success': true,
          'message': 'OTP sent successfully to your mobile number.',
          'otp': '482915',
          'deliveryMode': 'on_screen',
          'isAdmin': false,
        };
      };

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '9063663180');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Production/release guard never displays on-screen OTP
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.byKey(const Key('login_onscreen_otp_banner')), findsNothing);
      expect(find.textContaining('482915'), findsNothing);
      expect(find.byKey(const Key('login_otp_fill_button')), findsNothing);
    });

    testWidgets('Staging dynamic OTP works for any arbitrary valid 10-digit mobile number and displays OTP banner', (WidgetTester tester) async {
      ApiConstants.debugAllowOnScreenOtpOverride = true;
      String? requestedPhone;
      ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
        requestedPhone = phone;
        return {
          'success': true,
          'message': 'Verification code ready on screen (testing mode).',
          'otp': '731904',
          'deliveryMode': 'on_screen',
          'isAdmin': false,
        };
      };

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '9888877777');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(requestedPhone, '9888877777');
      expect(find.byKey(const Key('login_onscreen_otp_banner')), findsOneWidget);
      expect(find.text('Your verification code: 731904'), findsOneWidget);
    });

    testWidgets('Renders Responsive Two-Column Layout on Desktop Viewport (>900px)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080); // Desktop screen
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Desktop hero column features (Multi-Specialty Healthcare)
      expect(find.text('Comprehensive, expert medical care.'), findsOneWidget);
      expect(find.text('AI triage, verified doctors across all specialties, and your records, all in one place.'), findsOneWidget);
      expect(find.text('Verified Doctors'), findsOneWidget);
      expect(find.text('All Medical Specialties'), findsOneWidget);
      expect(find.text('Health Records & AI'), findsOneWidget);

      // Right login column form
      expect(find.text('Sign in with mobile'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
      expect(find.text('DEMO ACCOUNTS · TAP TO FILL'), findsNothing);
    });
  });
}
