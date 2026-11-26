import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/routes/app_router.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';

void _installGoogleFontsMock(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    if (message == null) return null;
    final key = utf8.decode(message.buffer.asUint8List());
    if (key == 'AssetManifest.json' || key == 'AssetManifest.bin') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode('{}')));
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SessionService().clearSession();
    PatientProblemService().clearSubAdminSession();
    PatientProblemService().setAdminMode(false);
    ApiService.debugRequestOtpOverride = null;
    ApiService.debugVerifyOtpOverride = null;
    ApiService.debugLoginOverride = null;
  });

  tearDown(() async {
    ApiService.debugRequestOtpOverride = null;
    ApiService.debugVerifyOtpOverride = null;
    ApiService.debugLoginOverride = null;
    await SessionService().clearSession();
  });

  group('GS Health — Admin OTP Login & Authorization Verification', () {
    test('1. ApiService.verifyOtp forwards accessToken, refreshToken, realtimeToken, isAdmin, and error code cleanly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/otp/verify'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['phone'], '9281030535');
        expect(body['code'], '805065');
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'OTP verified successfully.',
            'isAdmin': true,
            'isSubAdmin': false,
            'accessToken': 'jwt_admin_verified_token',
            'refreshToken': 'jwt_admin_refresh_token',
            'realtimeToken': 'sb_rt_admin_token',
            'realtimeTokenExpiresAt': '2030-01-01T00:00:00.000Z',
            'user': {
              'id': '339f745b-2192-4055-abec-d7e4adc6c837',
              'name': 'GS HEALTH Admin',
              'phone': '9281030535',
              'role': 'ADMIN',
              'status': 'ACTIVE',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final res = await ApiService().verifyOtp(
        phone: '9281030535',
        code: '805065',
        role: 'Admin',
        client: mockClient,
      );

      expect(res['success'], isTrue);
      expect(res['isAdmin'], isTrue);
      expect(res['accessToken'], 'jwt_admin_verified_token');
      expect(res['realtimeToken'], 'sb_rt_admin_token');
      expect(res['realtimeTokenExpiresAt'], '2030-01-01T00:00:00.000Z');
      expect((res['user'] as Map)['role'], 'ADMIN');
    });

    test('2. ApiService.verifyOtp returns backend 403 unauthorized error message without granting access', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'code': 'ACCOUNT_DEACTIVATED',
            'message': 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final res = await ApiService().verifyOtp(
        phone: '9844455566',
        code: '123456',
        role: 'Admin',
        client: mockClient,
      );

      expect(res['success'], isFalse);
      expect(res['status'], 403);
      expect(res['code'], 'ACCOUNT_DEACTIVATED');
      expect(res['message'], contains('Unauthorized Admin access'));
      expect(res['accessToken'], isNull);
    });

    testWidgets(
      '3. Admin entering country-code mobile (+91 92810 30535) normalizes cleanly, verifies OTP, saves ADMIN session, and opens Admin Dashboard',
      (WidgetTester tester) async {
        _installGoogleFontsMock(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        String? requestedPhone;
        String? verifiedPhone;

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
          requestedPhone = phone;
          return {
            'success': true,
            'message': 'Verification code ready on screen (testing mode).',
            'otp': '805065',
            'deliveryMode': 'on_screen',
            'isAdmin': phone == '9281030535',
          };
        };

        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async {
          verifiedPhone = phone;
          if (phone == '9281030535' && code == '805065') {
            return {
              'success': true,
              'message': 'OTP verified successfully.',
              'isAdmin': true,
              'accessToken': 'verified_admin_jwt_9281030535',
              'refreshToken': 'verified_admin_refresh_9281030535',
              'user': {
                'id': '339f745b-2192-4055-abec-d7e4adc6c837',
                'name': 'GS HEALTH Admin',
                'email': 'user_9281030535@dentaguru.internal',
                'phone': '9281030535',
                'role': 'ADMIN',
                'status': 'ACTIVE',
              },
            };
          }
          return {
            'success': false,
            'message': 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.',
          };
        };

        appRouter.go('/login');
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: appRouter),
          ),
        );
        await tester.pumpAndSettle();

        // Enter country-code formatted admin phone
        await tester.enterText(find.byType(TextFormField).first, '+91 92810 30535');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(requestedPhone, '9281030535');
        expect(find.text('Enter your code'), findsOneWidget);

        final digitInputs = find.byType(TextFormField);
        const digits = ['8', '0', '5', '0', '6', '5'];
        for (int i = 0; i < digits.length; i++) {
          await tester.enterText(digitInputs.at(i), digits[i]);
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final verifyBtnFinder = find.widgetWithText(ElevatedButton, 'Verify & continue');
        if (verifyBtnFinder.evaluate().isNotEmpty && find.text('Admin console').evaluate().isEmpty) {
          await tester.ensureVisible(verifyBtnFinder);
          await tester.pumpAndSettle();
          await tester.tap(verifyBtnFinder);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(verifiedPhone, '9281030535');
        expect(find.text('Admin console'), findsOneWidget);
        expect(SessionService().currentSession?.role, 'ADMIN');
        expect(SessionService().currentSession?.token, 'verified_admin_jwt_9281030535');
      },
    );

    testWidgets(
      '4. Unauthorized user rejected by backend stays on OTP screen with clear error and never enters Admin Dashboard',
      (WidgetTester tester) async {
        _installGoogleFontsMock(tester);
        tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        ApiService.debugRequestOtpOverride = ({required String phone, String email = ''}) async {
          return {
            'success': true,
            'message': 'OTP sent',
            'otp': '111222',
            'deliveryMode': 'on_screen',
            'isAdmin': false,
          };
        };

        ApiService.debugVerifyOtpOverride = ({required String phone, String email = '', required String code}) async {
          return {
            'success': false,
            'status': 403,
            'message': 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.',
          };
        };

        appRouter.go('/login?role=admin');
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: appRouter),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, '9844455566');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Send code'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final digitInputs = find.byType(TextFormField);
        const digits = ['1', '1', '1', '2', '2', '2'];
        for (int i = 0; i < digits.length; i++) {
          await tester.enterText(digitInputs.at(i), digits[i]);
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Unauthorized Admin access. OTP verification alone cannot grant Admin access.'), findsOneWidget);
        expect(find.text('Admin console'), findsNothing);
        expect(SessionService().currentSession, isNull);
      },
    );
  });
}
