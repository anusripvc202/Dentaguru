import 'dart:convert';
import 'dart:io';

import 'package:dentaguru/core/constants/api_constants.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    ApiConstants.debugBaseUrlOverride = null;
    ApiConstants.debugAllowOnScreenOtpOverride = null;
    SupabaseService.resetForTesting();
  });

  group('Flutter Debug & Release Environment Isolation', () {
    test('1. Debug mode using local test backend rejects production Supabase project ref', () async {
      bool initializerCalled = false;
      SupabaseService.debugSupabaseInitializer = ({
        required String url,
        required String anonKey,
        required bool debug,
      }) async {
        initializerCalled = true;
      };

      await expectLater(
        () => SupabaseService.initialize(
          isReleaseOverride: false,
          isDebugOverride: true,
          isWebOverride: false,
          platformOverride: TargetPlatform.android,
          testSupabaseUrlOverride: 'https://fommrwxpqzkcktweosgp.supabase.co',
          testSupabaseAnonKeyOverride: 'test_dummy_anon_key_non_secret',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Debug Isolation Error'),
              contains('fommrwxpqzkcktweosgp'),
              isNot(contains('test_dummy_anon_key_non_secret')),
            ),
          ),
        ),
      );

      expect(initializerCalled, isFalse);
      expect(SupabaseService.isInitialized, isFalse);
      expect(SupabaseService.initializedUrl, isNull);
    });

    test('2. Missing TEST_SUPABASE_URL / TEST_SUPABASE_ANON_KEY fails closed in debug mode', () async {
      bool initializerCalled = false;
      SupabaseService.debugSupabaseInitializer = ({
        required String url,
        required String anonKey,
        required bool debug,
      }) async {
        initializerCalled = true;
      };

      // Android debug with missing credentials
      await expectLater(
        () => SupabaseService.initialize(
          isReleaseOverride: false,
          isDebugOverride: true,
          isWebOverride: false,
          platformOverride: TargetPlatform.android,
          testSupabaseUrlOverride: '',
          testSupabaseAnonKeyOverride: '',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('TEST_SUPABASE_URL'),
              contains('TEST_SUPABASE_ANON_KEY'),
              contains('Refusing to fall back to production Supabase'),
            ),
          ),
        ),
      );

      // URL provided but anon key missing
      await expectLater(
        () => SupabaseService.initialize(
          isReleaseOverride: false,
          isDebugOverride: true,
          isWebOverride: false,
          platformOverride: TargetPlatform.android,
          testSupabaseUrlOverride: 'https://ojinzcdldwugpnxrnjcq.supabase.co',
          testSupabaseAnonKeyOverride: '',
        ),
        throwsA(isA<StateError>()),
      );

      expect(initializerCalled, isFalse);
      expect(SupabaseService.isInitialized, isFalse);
      expect(SupabaseService.lastInitError, isNotNull);
    });

    test('3. Valid test credentials initialize dedicated gs-health-test Supabase project', () async {
      String? capturedUrl;
      String? capturedKey;
      bool? capturedDebug;

      SupabaseService.debugSupabaseInitializer = ({
        required String url,
        required String anonKey,
        required bool debug,
      }) async {
        capturedUrl = url;
        capturedKey = anonKey;
        capturedDebug = debug;
      };

      await SupabaseService.initialize(
        isReleaseOverride: false,
        isDebugOverride: true,
        isWebOverride: false,
        platformOverride: TargetPlatform.android,
        testSupabaseUrlOverride: 'https://ojinzcdldwugpnxrnjcq.supabase.co/',
        testSupabaseAnonKeyOverride: 'gs_health_test_anon_key_fixture',
      );

      expect(capturedUrl, 'https://ojinzcdldwugpnxrnjcq.supabase.co');
      expect(capturedKey, 'gs_health_test_anon_key_fixture');
      expect(capturedDebug, isTrue);
      expect(SupabaseService.isInitialized, isTrue);
      expect(SupabaseService.initializedUrl, 'https://ojinzcdldwugpnxrnjcq.supabase.co');
      expect(SupabaseService.lastInitError, isNull);

      // Also verify Android emulator baseUrl resolves to 10.0.2.2:5000
      final androidDebugUrl = ApiConstants.resolveBaseUrl(
        isRelease: false,
        isDebug: true,
        isWeb: false,
        platform: TargetPlatform.android,
        testApiUrl: '',
        localApiUrl: '',
      );
      expect(androidDebugUrl, 'http://10.0.2.2:5000/api/v1');
    });

    test('4. Release mode remains strictly locked to production Render and production Supabase', () async {
      String? capturedUrl;

      SupabaseService.debugSupabaseInitializer = ({
        required String url,
        required String anonKey,
        required bool debug,
      }) async {
        capturedUrl = url;
      };

      final releaseBaseUrl = ApiConstants.resolveBaseUrl(
        isRelease: true,
        isDebug: false,
        isWeb: false,
        platform: TargetPlatform.android,
        testApiUrl: 'https://dentaguru-backend-test.onrender.com/api/v1',
        localApiUrl: 'http://10.0.2.2:5000/api/v1',
      );
      expect(releaseBaseUrl, ApiConstants.liveBackendUrl);
      expect(releaseBaseUrl, 'https://dentaguru-backend.onrender.com/api/v1');

      await SupabaseService.initialize(
        isReleaseOverride: true,
        isDebugOverride: false,
        isWebOverride: false,
        platformOverride: TargetPlatform.android,
        testApiUrlOverride: 'http://10.0.2.2:5000/api/v1',
        testSupabaseUrlOverride: 'https://ojinzcdldwugpnxrnjcq.supabase.co',
        testSupabaseAnonKeyOverride: 'gs_health_test_anon_key_fixture',
      );

      expect(capturedUrl, 'https://fommrwxpqzkcktweosgp.supabase.co');
      expect(SupabaseService.isInitialized, isTrue);
    });

    test('5. fetchClinics uses ApiConstants.baseUrl only and has no hardcoded localhost fallback', () async {
      final requestedUris = <Uri>[];
      final mockSuccessClient = MockClient((request) async {
        requestedUris.add(request.url);
        return http.Response(
          jsonEncode({
            'clinics': [
              {'id': 'c1', 'clinic_name': 'GS Test Clinic'}
            ]
          }),
          200,
        );
      });

      final clinics = await ApiService().fetchClinics(client: mockSuccessClient);
      expect(clinics.length, 1);
      expect(requestedUris.length, 1);
      expect(requestedUris.first.toString(), '${ApiConstants.baseUrl}/clinics');

      // When the configured API fails, fetchClinics must NOT retry http://localhost:5000/api/v1/clinics
      final failedAttemptUris = <Uri>[];
      final mockFailClient = MockClient((request) async {
        failedAttemptUris.add(request.url);
        throw const SocketException('Simulated network failure');
      });

      final emptyResult = await ApiService().fetchClinics(client: mockFailClient);
      expect(emptyResult, isEmpty);
      expect(failedAttemptUris.length, 1);
      expect(failedAttemptUris.first.toString(), '${ApiConstants.baseUrl}/clinics');

      // Static source check confirming the hardcoded localhost fallback was removed
      final apiServiceSource = File('lib/core/services/api_service.dart').readAsStringSync();
      expect(apiServiceSource.contains('http://localhost:5000/api/v1/clinics'), isFalse);
    });

    test('6. Staging TEST_API_URL resolves cloud testing URL without localhost fallback in requestOtp/verifyOtp', () async {
      final stagingUrl = ApiConstants.resolveBaseUrl(
        isRelease: false,
        isDebug: true,
        isWeb: false,
        platform: TargetPlatform.android,
        testApiUrl: ApiConstants.stagingBackendUrl,
        localApiUrl: '',
      );
      expect(stagingUrl, 'https://dentaguru-backend-test.onrender.com/api/v1');

      ApiConstants.debugBaseUrlOverride = stagingUrl;
      ApiConstants.debugAllowOnScreenOtpOverride = true;
      expect(ApiConstants.isUsingLocalhostBackend, isFalse);

      final otpCandidates = ApiService.candidateEndpointUrls('/auth/otp/request');
      expect(otpCandidates.length, 1);
      expect(
        otpCandidates.first.toString(),
        'https://dentaguru-backend-test.onrender.com/api/v1/auth/otp/request',
      );
      expect(otpCandidates.any((u) => u.host == 'localhost' || u.host == '127.0.0.1'), isFalse);

      // Staging requestOtp calls ONLY staging backend & returns on-screen OTP
      final attemptedUrls = <Uri>[];
      final stagingOtpClient = MockClient((request) async {
        attemptedUrls.add(request.url);
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Verification code ready on screen (testing mode).',
            'otp': '654321',
            'deliveryMode': 'on_screen',
            'isAdmin': false,
          }),
          200,
        );
      });

      final otpResult = await ApiService().requestOtp(
        phone: '9281030535',
        client: stagingOtpClient,
      );
      expect(otpResult['success'], isTrue);
      expect(otpResult['deliveryMode'], 'on_screen');
      expect(otpResult['otp'], '654321');
      expect(attemptedUrls.length, 1);
      expect(
        attemptedUrls.first.toString(),
        'https://dentaguru-backend-test.onrender.com/api/v1/auth/otp/request',
      );

      // On network failure against cloud staging URL, must NOT retry localhost or generate local fake OTP
      final failedUrls = <Uri>[];
      final failClient = MockClient((request) async {
        failedUrls.add(request.url);
        throw const SocketException('Staging unreachable');
      });

      final failResult = await ApiService().requestOtp(
        phone: '9281030535',
        client: failClient,
      );
      expect(failResult['success'], isFalse);
      expect(failResult['otp'], isNull);
      expect(failResult['message'], contains('Unable to reach testing OTP backend'));
      expect(failedUrls.length, 1);
      expect(failedUrls.first.host, 'dentaguru-backend-test.onrender.com');
    });
  });
}
