import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  /// Live 24/7 Production Render Express Backend API URL (Connected to Production Supabase)
  static const String liveBackendUrl = 'https://dentaguru-backend.onrender.com/api/v1';

  /// Localhost Backend API URL (Debug builds only — Web / Desktop / iOS simulator)
  static const String localBackendUrl = 'http://localhost:5000/api/v1';

  /// Local Android Emulator Backend API URL (Debug builds only — maps emulator to host localhost:5000)
  static const String androidEmulatorLocalUrl = 'http://10.0.2.2:5000/api/v1';

  /// Production Supabase project reference (strictly forbidden in debug/local testing mode)
  static const String productionSupabaseProjectRef = 'fommrwxpqzkcktweosgp';

  /// Default Production Supabase Cloud Credentials (used ONLY in release builds, or profile builds targeting production)
  static const String _prodSupabaseUrl = 'https://fommrwxpqzkcktweosgp.supabase.co';
  static const String _prodSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvbW1yd3hwcXprY2t0d2Vvc2dwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4MTM3MTAsImV4cCI6MjEwMTM4OTcxMH0.VcuNyxIEeUDMGzMf3upGHzDCE_ihdYn0qZY5sjdOD3g';

  /// Non-release compile-time overrides for temporary Render testing service & separate testing Supabase project.
  /// Strictly ignored in `kReleaseMode` — release builds ALWAYS connect to production.
  /// Example:
  ///   flutter run \
  ///     --dart-define=TEST_API_URL=https://dentaguru-backend-test.onrender.com/api/v1 \
  ///     --dart-define=TEST_SUPABASE_URL=https://<your-test-ref>.supabase.co \
  ///     --dart-define=TEST_SUPABASE_ANON_KEY=<your-test-anon-key>
  static const String _testApiUrl = String.fromEnvironment('TEST_API_URL', defaultValue: '');
  static const String _localApiUrl = String.fromEnvironment('LOCAL_API_URL', defaultValue: '');
  static const String _testSupabaseUrl = String.fromEnvironment('TEST_SUPABASE_URL', defaultValue: '');
  static const String _testSupabaseAnonKey = String.fromEnvironment('TEST_SUPABASE_ANON_KEY', defaultValue: '');

  /// Explicit compile-time testing flag for profile builds (false by default).
  static const bool _profileOtpTestDisplayFlag = bool.fromEnvironment('OTP_TEST_DISPLAY', defaultValue: false);

  /// Compile-time testing flag for debug builds (enabled by default in debug; can be turned off via OTP_TEST_DISPLAY=false).
  static const bool _debugOtpTestDisplayFlag = bool.fromEnvironment('OTP_TEST_DISPLAY', defaultValue: true);

  @visibleForTesting
  static bool? debugAllowOnScreenOtpOverride;

  /// On-screen OTP testing display guard:
  /// - Release builds (`kReleaseMode`): NEVER allowed (unconditionally false).
  /// - Profile builds (`kProfileMode`): Disabled by default (`false` unless explicitly opted in).
  /// - Debug builds (`kDebugMode`): Permitted when backend returns `deliveryMode == 'on_screen'`.
  static bool get allowOnScreenOtpDisplay {
    if (kReleaseMode) return false;
    if (debugAllowOnScreenOtpOverride != null) return debugAllowOnScreenOtpOverride!;
    if (kDebugMode) return _debugOtpTestDisplayFlag;
    return _profileOtpTestDisplayFlag;
  }

  /// Returns true if the supplied Supabase URL or anon key belongs to the production Supabase project.
  static bool isProductionSupabaseConfig({
    required String url,
    required String anonKey,
  }) {
    final normalizedUrl = url.trim().toLowerCase();
    final normalizedKey = anonKey.trim();
    return normalizedUrl.contains(productionSupabaseProjectRef) ||
        (normalizedKey.isNotEmpty && normalizedKey == _prodSupabaseAnonKey);
  }

  /// Resolves the Express Backend API Base URL for the given runtime mode and platform.
  /// - Release builds ALWAYS use live 24/7 production Render server
  /// - Non-release testing builds may override via TEST_API_URL or LOCAL_API_URL
  /// - Debug builds default to localhost:5000 on Web/Desktop and 10.0.2.2:5000 on Android emulator
  static String resolveBaseUrl({
    bool isRelease = kReleaseMode,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
  }) {
    if (!isRelease) {
      final TargetPlatform effectivePlatform = platform ?? defaultTargetPlatform;
      final bool isAndroidNative = !isWeb && effectivePlatform == TargetPlatform.android;
      final String configured = testApiUrl.trim().isNotEmpty ? testApiUrl.trim() : localApiUrl.trim();
      if (configured.isNotEmpty) {
        if (isAndroidNative && configured.contains('://localhost:')) {
          return configured.replaceFirst('://localhost:', '://10.0.2.2:');
        }
        if (!isAndroidNative && configured.contains('://10.0.2.2:')) {
          return configured.replaceFirst('://10.0.2.2:', '://localhost:');
        }
        return configured;
      }
      if (isDebug) {
        return isAndroidNative ? androidEmulatorLocalUrl : localBackendUrl;
      }
    }
    return liveBackendUrl;
  }

  /// Returns true when a non-release build is targeting a local or test backend URL.
  static bool isUsingNonProductionBackend({
    bool isRelease = kReleaseMode,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
  }) {
    if (isRelease) return false;
    final String resolved = resolveBaseUrl(
      isRelease: isRelease,
      isDebug: isDebug,
      isWeb: isWeb,
      platform: platform,
      testApiUrl: testApiUrl,
      localApiUrl: localApiUrl,
    );
    return resolved.trim().toLowerCase() != liveBackendUrl.trim().toLowerCase();
  }

  /// Fail-closed Supabase configuration resolver:
  /// - Release builds (`kReleaseMode`): ALWAYS locked to production Supabase.
  /// - Debug builds (`kDebugMode`) or any non-release build using a non-production backend:
  ///   STRICTLY requires TEST_SUPABASE_URL and TEST_SUPABASE_ANON_KEY and NEVER falls back
  ///   to production Supabase (`fommrwxpqzkcktweosgp`). Throws a non-sensitive [StateError]
  ///   if missing or pointing to production.
  static ({String url, String anonKey}) resolveSupabaseConfig({
    bool isRelease = kReleaseMode,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
    String testSupabaseUrl = _testSupabaseUrl,
    String testSupabaseAnonKey = _testSupabaseAnonKey,
  }) {
    if (isRelease) {
      return (url: _prodSupabaseUrl, anonKey: _prodSupabaseAnonKey);
    }

    final String cleanUrl = testSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String cleanKey = testSupabaseAnonKey.trim();

    final bool requiresIsolatedTestSupabase = isDebug ||
        isUsingNonProductionBackend(
          isRelease: isRelease,
          isDebug: isDebug,
          isWeb: isWeb,
          platform: platform,
          testApiUrl: testApiUrl,
          localApiUrl: localApiUrl,
        );

    if (requiresIsolatedTestSupabase) {
      if (cleanUrl.isEmpty || cleanKey.isEmpty) {
        throw StateError(
          'GS HEALTH Debug Isolation Error: TEST_SUPABASE_URL and TEST_SUPABASE_ANON_KEY '
          'must be configured in debug/testing mode via --dart-define. '
          'Refusing to fall back to production Supabase.',
        );
      }

      if (isProductionSupabaseConfig(url: cleanUrl, anonKey: cleanKey)) {
        throw StateError(
          'GS HEALTH Debug Isolation Error: Debug/testing builds cannot connect to '
          'production Supabase project ($productionSupabaseProjectRef). '
          'Configure dedicated test Supabase credentials via --dart-define=TEST_SUPABASE_URL '
          'and --dart-define=TEST_SUPABASE_ANON_KEY.',
        );
      }

      final String lowerUrl = cleanUrl.toLowerCase();
      if (!lowerUrl.startsWith('https://') && !lowerUrl.startsWith('http://')) {
        throw StateError(
          'GS HEALTH Debug Isolation Error: TEST_SUPABASE_URL must be a valid HTTP(S) Supabase project URL.',
        );
      }

      return (url: cleanUrl, anonKey: cleanKey);
    }

    // Non-debug profile builds explicitly overriding test Supabase credentials
    if (cleanUrl.isNotEmpty || cleanKey.isNotEmpty) {
      if (cleanUrl.isEmpty || cleanKey.isEmpty) {
        throw StateError(
          'GS HEALTH Configuration Error: Both TEST_SUPABASE_URL and TEST_SUPABASE_ANON_KEY '
          'must be provided together.',
        );
      }
      return (url: cleanUrl, anonKey: cleanKey);
    }

    return (url: _prodSupabaseUrl, anonKey: _prodSupabaseAnonKey);
  }

  /// Supabase Cloud URL (fail-closed in debug/testing mode; locked to production in release builds)
  static String get supabaseUrl => resolveSupabaseConfig().url;

  /// Supabase Cloud Anon Key (fail-closed in debug/testing mode; locked to production in release builds)
  static String get supabaseAnonKey => resolveSupabaseConfig().anonKey;

  /// Express Backend API Base URL
  /// - Release builds ALWAYS use live 24/7 production Render server
  /// - Non-release testing builds may override via TEST_API_URL or LOCAL_API_URL
  /// - Debug builds default to localhost:5000 on Web/Desktop and 10.0.2.2:5000 on Android emulator
  static String get baseUrl => resolveBaseUrl();

  // Authentication Endpoints
  static String get login => '$baseUrl/auth/login';
  static String get register => '$baseUrl/auth/register';
  static String get requestOtp => '$baseUrl/auth/otp/request';
  static String get verifyOtp => '$baseUrl/auth/otp/verify';
  static String get fcmToken => '$baseUrl/auth/fcm-token';
  static String get biometric => '$baseUrl/auth/biometric';

  // Appointments Endpoints
  static String get appointments => '$baseUrl/appointments';

  // Clinic Profile Endpoints
  static String get clinics => '$baseUrl/clinics';

  // AWS S3 Cloud Storage Endpoints
  static String get upload => '$baseUrl/upload';
  static String get signedUrl => '$baseUrl/upload/signed-url';

  // Chat Endpoints
  static String get chatSend => '$baseUrl/chat/send';

  // Medical Records Endpoints
  static String get records => '$baseUrl/records';

  // Referral & Organic Growth Endpoints
  static String get myReferrals => '$baseUrl/referrals/my-referrals';
  static String get allReferralsAdmin => '$baseUrl/referrals/all';
  static String get referralAnalytics => '$baseUrl/referrals/analytics';
}
