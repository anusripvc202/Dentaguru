import 'dart:convert';
import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  /// Live 24/7 Production Render Express Backend API URL (Connected to Production Supabase)
  static const String liveBackendUrl = 'https://dentaguru-backend.onrender.com/api/v1';

  /// Live 24/7 Testing/Staging Render Express Backend API URL (Connected to Testing Supabase)
  static const String stagingBackendUrl = 'https://dentaguru-backend-test.onrender.com/api/v1';

  /// Localhost Backend API URL (Debug builds only — Web / Desktop / iOS simulator)
  static const String localBackendUrl = 'http://localhost:5000/api/v1';

  /// Local Android Emulator Backend API URL (Debug builds only — maps emulator to host localhost:5000)
  static const String androidEmulatorLocalUrl = 'http://10.0.2.2:5000/api/v1';

  /// Production Supabase project reference (strictly forbidden in debug/local testing mode)
  static const String productionSupabaseProjectRef = 'fommrwxpqzkcktweosgp';

  /// Staging Supabase project reference (strictly required in profile mode)
  static const String stagingSupabaseProjectRef = 'ojinzcdldwugpnxrnjcq';
  static const String _stagingSupabaseUrl = 'https://$stagingSupabaseProjectRef.supabase.co';

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

  /// Compile-time flavor identifier populated automatically by Flutter when building with `--flavor staging` / `--flavor production`.
  static const String _appFlavor = String.fromEnvironment('FLUTTER_APP_FLAVOR', defaultValue: '');

  /// True ONLY when compiled using the dedicated `staging` flavor (`flutter build apk --flavor staging ...`).
  static const bool isStagingFlavorBuild = _appFlavor == 'staging';

  /// Staging-only OTP access key supplied via --dart-define=STAGING_OTP_ACCESS_KEY=... for internal staging QA builds ONLY.
  /// Never hardcoded in source code and never compiled/sent in public production release builds (`kReleaseMode && !isStagingFlavorBuild`).
  static const String _stagingOtpAccessKey = String.fromEnvironment('STAGING_OTP_ACCESS_KEY', defaultValue: '');

  /// Explicit compile-time testing flag for profile / staging builds (false by default).
  static const bool _profileOtpTestDisplayFlag = bool.fromEnvironment('OTP_TEST_DISPLAY', defaultValue: false);

  /// Compile-time testing flag for debug builds (enabled by default in debug; can be turned off via OTP_TEST_DISPLAY=false).
  static const bool _debugOtpTestDisplayFlag = bool.fromEnvironment('OTP_TEST_DISPLAY', defaultValue: true);

  @visibleForTesting
  static bool? debugAllowOnScreenOtpOverride;

  @visibleForTesting
  static String? debugBaseUrlOverride;

  @visibleForTesting
  static String? debugStagingOtpAccessKeyOverride;

  /// On-screen OTP testing display guard:
  /// - Public production release builds (`kReleaseMode && !isStagingFlavorBuild`): NEVER allowed (unconditionally false).
  /// - Dedicated staging flavor builds (`isStagingFlavorBuild`): Permitted ONLY when `OTP_TEST_DISPLAY=true` is explicitly compiled in.
  /// - Profile builds (`kProfileMode`): Disabled by default (`false` unless explicitly opted in).
  /// - Debug builds (`kDebugMode`): Permitted when backend returns `deliveryMode == 'on_screen'`.
  static bool get allowOnScreenOtpDisplay {
    if (isStagingFlavorBuild) {
      if (debugAllowOnScreenOtpOverride != null) return debugAllowOnScreenOtpOverride!;
      return _profileOtpTestDisplayFlag;
    }
    if (kReleaseMode) return false;
    if (debugAllowOnScreenOtpOverride != null) return debugAllowOnScreenOtpOverride!;
    if (kDebugMode) return _debugOtpTestDisplayFlag;
    return _profileOtpTestDisplayFlag;
  }

  /// Resolves the staging-only OTP access key header value:
  /// - Public production release builds (`isRelease && !isStagingFlavor`): ALWAYS empty (never exposed or sent).
  /// - When targeting the production backend URL: ALWAYS empty.
  /// - When on-screen OTP display is disabled: ALWAYS empty.
  /// - Authorized staging flavor or non-release QA builds targeting staging backend: returns compile-time STAGING_OTP_ACCESS_KEY if provided.
  static String resolveStagingOtpAccessKey({
    bool isRelease = kReleaseMode,
    bool isStagingFlavor = isStagingFlavorBuild,
    bool? allowOnScreenOtp,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
    String? baseUrlOverride,
    String stagingOtpAccessKey = _stagingOtpAccessKey,
  }) {
    if (isStagingFlavor) {
      final bool canDisplay = allowOnScreenOtp ?? allowOnScreenOtpDisplay;
      if (!canDisplay) return '';
      final String effectiveUrl = (baseUrlOverride ??
              _resolveStagingFlavorBaseUrl(testApiUrl: testApiUrl))
          .trim()
          .toLowerCase();
      final String host = Uri.tryParse(effectiveUrl)?.host.trim().toLowerCase() ?? '';
      if (host != Uri.parse(stagingBackendUrl).host.trim().toLowerCase()) {
        return '';
      }
      return stagingOtpAccessKey.trim();
    }

    if (isRelease) return '';
    final bool canDisplay = allowOnScreenOtp ?? allowOnScreenOtpDisplay;
    if (!canDisplay) return '';

    final String effectiveUrl = (baseUrlOverride ??
            resolveBaseUrl(
              isRelease: isRelease,
              isStagingFlavor: false,
              isDebug: isDebug,
              isWeb: isWeb,
              platform: platform,
              testApiUrl: testApiUrl,
              localApiUrl: localApiUrl,
            ))
        .trim()
        .toLowerCase();
    if (effectiveUrl == liveBackendUrl.trim().toLowerCase()) {
      return '';
    }
    return stagingOtpAccessKey.trim();
  }

  /// Compile-time staging OTP secret key for authorized staging / non-release QA builds (`''` in public production release builds).
  static String get stagingOtpAccessKey {
    if (isStagingFlavorBuild) {
      return resolveStagingOtpAccessKey(
        isRelease: kReleaseMode,
        isStagingFlavor: true,
        baseUrlOverride: debugBaseUrlOverride,
        stagingOtpAccessKey: debugStagingOtpAccessKeyOverride ?? _stagingOtpAccessKey,
      );
    }
    if (kReleaseMode) return '';
    return resolveStagingOtpAccessKey(
      isStagingFlavor: false,
      baseUrlOverride: debugBaseUrlOverride,
      stagingOtpAccessKey: debugStagingOtpAccessKeyOverride ?? _stagingOtpAccessKey,
    );
  }

  /// Safely decodes a Supabase JWT payload locally without logging or exposing the token.
  static Map<String, dynamic>? _tryDecodeJwtClaims(String token) {
    final String trimmed = token.trim();
    final List<String> parts = trimmed.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      return null;
    }
    try {
      final String normalized = base64Url.normalize(parts[1]);
      final String jsonStr = utf8.decode(base64Url.decode(normalized));
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts `<ref>` from an exact `https://<ref>.supabase.co` URL, or `null` if invalid/spoofed.
  static String? _extractSupabaseUrlProjectRef(String url) {
    final Uri? parsed = Uri.tryParse(url.trim());
    if (parsed == null) return null;
    final String scheme = parsed.scheme.toLowerCase();
    final String host = parsed.host.trim().toLowerCase();
    if (scheme != 'https' ||
        !host.endsWith('.supabase.co') ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.hasPort) {
      return null;
    }
    final String ref = host.substring(0, host.length - '.supabase.co'.length);
    if (ref.isEmpty || ref.contains('.')) {
      return null;
    }
    return ref;
  }

  /// Returns true if the supplied Supabase URL or anon key belongs to the production Supabase project.
  static bool isProductionSupabaseConfig({
    required String url,
    required String anonKey,
  }) {
    final normalizedUrl = url.trim().toLowerCase();
    final normalizedKey = anonKey.trim();
    final Map<String, dynamic>? claims = normalizedKey.isNotEmpty
        ? _tryDecodeJwtClaims(normalizedKey)
        : null;
    final String? tokenRef = claims?['ref']?.toString().trim().toLowerCase();
    return normalizedUrl.contains(productionSupabaseProjectRef) ||
        (normalizedKey.isNotEmpty && normalizedKey == _prodSupabaseAnonKey) ||
        tokenRef == productionSupabaseProjectRef;
  }

  /// Returns true if the supplied backend API URL points to the live production Render host.
  static bool isProductionBackendUrl(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final String lower = trimmed.toLowerCase().replaceAll(RegExp(r'/+$'), '');
    final Uri? parsed = Uri.tryParse(trimmed);
    final String host = parsed?.host.trim().toLowerCase() ?? '';
    final String prodHost = Uri.parse(liveBackendUrl).host.trim().toLowerCase();
    return host == prodHost ||
        lower == liveBackendUrl.trim().toLowerCase() ||
        lower.startsWith('https://$prodHost') ||
        lower.startsWith('http://$prodHost');
  }

  static bool _isValidHttpUrl(String url) {
    final Uri? parsed = Uri.tryParse(url.trim());
    if (parsed == null) return false;
    final String scheme = parsed.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && parsed.host.trim().isNotEmpty;
  }

  static String _adaptLocalhostForPlatform(String url, {required bool isAndroidNative}) {
    if (isAndroidNative && url.contains('://localhost:')) {
      return url.replaceFirst('://localhost:', '://10.0.2.2:');
    }
    if (!isAndroidNative && url.contains('://10.0.2.2:')) {
      return url.replaceFirst('://10.0.2.2:', '://localhost:');
    }
    return url;
  }

  /// Strict allowlist resolver for the dedicated Android `staging` flavor.
  /// Never references production URLs so AOT tree-shaking excludes production hosts from staging APKs.
  static String _resolveStagingFlavorBaseUrl({
    String testApiUrl = _testApiUrl,
  }) {
    final String cleanTestApiUrl = testApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String effective = cleanTestApiUrl.isEmpty ? stagingBackendUrl : cleanTestApiUrl;
    if (!_isValidHttpUrl(effective)) {
      throw StateError(
        'GS HEALTH Staging Isolation Error: TEST_API_URL must be a valid HTTPS staging URL.',
      );
    }
    final Uri parsed = Uri.parse(effective);
    final String expectedHost = Uri.parse(stagingBackendUrl).host.trim().toLowerCase();
    if (parsed.scheme.toLowerCase() != 'https' || parsed.host.trim().toLowerCase() != expectedHost) {
      throw StateError(
        'GS HEALTH Staging Isolation Error: Staging flavor builds are strictly restricted to $stagingBackendUrl.',
      );
    }
    return effective;
  }

  /// Strict allowlist Supabase resolver for the dedicated Android `staging` flavor.
  /// Never references production Supabase URLs or anon keys so AOT tree-shaking excludes them from staging APKs.
  static ({String url, String anonKey}) _resolveStagingFlavorSupabaseConfig({
    String testApiUrl = _testApiUrl,
    String testSupabaseUrl = _testSupabaseUrl,
    String testSupabaseAnonKey = _testSupabaseAnonKey,
  }) {
    _resolveStagingFlavorBaseUrl(testApiUrl: testApiUrl);

    final String cleanUrl = testSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String cleanKey = testSupabaseAnonKey.trim();

    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      throw StateError(
        'GS HEALTH Staging Isolation Error: TEST_SUPABASE_URL and TEST_SUPABASE_ANON_KEY '
        'must be provided via --dart-define for staging flavor builds.',
      );
    }

    final String? urlRef = _extractSupabaseUrlProjectRef(cleanUrl);
    if (urlRef == null || urlRef != stagingSupabaseProjectRef) {
      throw StateError(
        'GS HEALTH Staging Isolation Error: Staging flavor builds are strictly restricted to '
        'staging Supabase project ($stagingSupabaseProjectRef) at $_stagingSupabaseUrl.',
      );
    }

    final Map<String, dynamic>? claims = _tryDecodeJwtClaims(cleanKey);
    if (claims == null) {
      throw StateError(
        'GS HEALTH Staging Isolation Error: TEST_SUPABASE_ANON_KEY must be a valid JWT '
        'for staging project ($stagingSupabaseProjectRef).',
      );
    }

    final String tokenRef = (claims['ref'] ?? '').toString().trim().toLowerCase();
    final String tokenRole = (claims['role'] ?? '').toString().trim().toLowerCase();
    final String tokenIss = (claims['iss'] ?? '').toString().trim().toLowerCase();

    if (tokenRef != stagingSupabaseProjectRef) {
      throw StateError(
        'GS HEALTH Staging Isolation Error: TEST_SUPABASE_ANON_KEY project ref must match '
        'staging project ($stagingSupabaseProjectRef).',
      );
    }
    if (tokenRole != 'anon') {
      throw StateError(
        'GS HEALTH Staging Isolation Error: TEST_SUPABASE_ANON_KEY JWT must have role "anon".',
      );
    }
    if (tokenIss.isNotEmpty && tokenIss != 'supabase') {
      throw StateError(
        'GS HEALTH Staging Isolation Error: TEST_SUPABASE_ANON_KEY JWT has invalid issuer.',
      );
    }

    return (url: cleanUrl, anonKey: cleanKey);
  }

  /// Resolves the Express Backend API Base URL for the given runtime mode, flavor, and platform.
  /// - Dedicated `staging` flavor builds ALWAYS resolve strictly to staging Render (`dentaguru-backend-test.onrender.com`)
  /// - Public production release builds ALWAYS use live 24/7 production Render server
  /// - Profile builds STRICTLY require a valid non-production TEST_API_URL (fail closed)
  /// - Debug builds support TEST_API_URL / LOCAL_API_URL or default to localhost / 10.0.2.2
  static String resolveBaseUrl({
    bool isRelease = kReleaseMode,
    bool isStagingFlavor = isStagingFlavorBuild,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
  }) {
    if (isStagingFlavor) {
      return _resolveStagingFlavorBaseUrl(testApiUrl: testApiUrl);
    }
    if (isRelease) {
      return liveBackendUrl;
    }

    final TargetPlatform effectivePlatform = platform ?? defaultTargetPlatform;
    final bool isAndroidNative = !isWeb && effectivePlatform == TargetPlatform.android;
    final String cleanTestApiUrl = testApiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String cleanLocalApiUrl = localApiUrl.trim().replaceAll(RegExp(r'/+$'), '');

    if (!isDebug) {
      if (cleanTestApiUrl.isEmpty) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: TEST_API_URL must be configured via '
          '--dart-define=TEST_API_URL=... in profile mode. Refusing to fall back to production backend.',
        );
      }
      if (!_isValidHttpUrl(cleanTestApiUrl)) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: TEST_API_URL must be a valid HTTP(S) URL.',
        );
      }
      if (isProductionBackendUrl(cleanTestApiUrl)) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: Profile builds cannot target the production backend URL. '
          'Configure a dedicated staging URL via --dart-define=TEST_API_URL.',
        );
      }
      return _adaptLocalhostForPlatform(cleanTestApiUrl, isAndroidNative: isAndroidNative);
    }

    final String configured = cleanTestApiUrl.isNotEmpty ? cleanTestApiUrl : cleanLocalApiUrl;
    if (configured.isNotEmpty) {
      if (!_isValidHttpUrl(configured)) {
        throw StateError(
          'GS HEALTH Debug Isolation Error: Configured TEST_API_URL / LOCAL_API_URL must be a valid HTTP(S) URL.',
        );
      }
      if (isProductionBackendUrl(configured)) {
        throw StateError(
          'GS HEALTH Debug Isolation Error: Debug builds cannot target the production backend URL. '
          'Configure a dedicated staging or local backend URL.',
        );
      }
      return _adaptLocalhostForPlatform(configured, isAndroidNative: isAndroidNative);
    }

    return isAndroidNative ? androidEmulatorLocalUrl : localBackendUrl;
  }

  /// Returns true when the resolved backend base URL points to localhost, 127.0.0.1, or 10.0.2.2.
  static bool get isUsingLocalhostBackend {
    final normalized = baseUrl.trim().toLowerCase();
    return normalized.contains('://localhost:') ||
        normalized.contains('://127.0.0.1:') ||
        normalized.contains('://10.0.2.2:');
  }

  /// Returns true when a staging or non-release build is targeting a local or test backend URL.
  static bool isUsingNonProductionBackend({
    bool isRelease = kReleaseMode,
    bool isStagingFlavor = isStagingFlavorBuild,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
  }) {
    if (isStagingFlavor) return true;
    if (isRelease) return false;
    final String resolved = resolveBaseUrl(
      isRelease: isRelease,
      isStagingFlavor: false,
      isDebug: isDebug,
      isWeb: isWeb,
      platform: platform,
      testApiUrl: testApiUrl,
      localApiUrl: localApiUrl,
    );
    return resolved.trim().toLowerCase() != liveBackendUrl.trim().toLowerCase();
  }

  /// Fail-closed Supabase configuration resolver:
  /// - Dedicated `staging` flavor builds: STRICTLY locked to staging Supabase (`ojinzcdldwugpnxrnjcq`).
  /// - Public production release builds (`kReleaseMode && !isStagingFlavor`): ALWAYS locked to production Supabase.
  /// - Debug and Profile builds (`!kReleaseMode`): STRICTLY require valid non-production
  ///   TEST_SUPABASE_URL and TEST_SUPABASE_ANON_KEY (and valid non-production TEST_API_URL
  ///   in profile mode) and NEVER fall back to production Supabase (`fommrwxpqzkcktweosgp`).
  static ({String url, String anonKey}) resolveSupabaseConfig({
    bool isRelease = kReleaseMode,
    bool isStagingFlavor = isStagingFlavorBuild,
    bool isDebug = kDebugMode,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    String testApiUrl = _testApiUrl,
    String localApiUrl = _localApiUrl,
    String testSupabaseUrl = _testSupabaseUrl,
    String testSupabaseAnonKey = _testSupabaseAnonKey,
  }) {
    if (isStagingFlavor) {
      return _resolveStagingFlavorSupabaseConfig(
        testApiUrl: testApiUrl,
        testSupabaseUrl: testSupabaseUrl,
        testSupabaseAnonKey: testSupabaseAnonKey,
      );
    }
    if (isRelease) {
      return (url: _prodSupabaseUrl, anonKey: _prodSupabaseAnonKey);
    }

    resolveBaseUrl(
      isRelease: false,
      isDebug: isDebug,
      isWeb: isWeb,
      platform: platform,
      testApiUrl: testApiUrl,
      localApiUrl: localApiUrl,
    );

    final String cleanUrl = testSupabaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String cleanKey = testSupabaseAnonKey.trim();
    final String modeLabel = isDebug ? 'Debug' : 'Profile';

    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      throw StateError(
        'GS HEALTH $modeLabel Isolation Error: TEST_SUPABASE_URL and TEST_SUPABASE_ANON_KEY '
        'must be configured in ${modeLabel.toLowerCase()} mode via --dart-define. '
        'Refusing to fall back to production Supabase.',
      );
    }

    if (isProductionSupabaseConfig(url: cleanUrl, anonKey: cleanKey)) {
      throw StateError(
        'GS HEALTH $modeLabel Isolation Error: $modeLabel builds cannot connect to '
        'production Supabase project ($productionSupabaseProjectRef). '
        'Configure dedicated test Supabase credentials via --dart-define=TEST_SUPABASE_URL '
        'and --dart-define=TEST_SUPABASE_ANON_KEY.',
      );
    }

    if (!_isValidHttpUrl(cleanUrl)) {
      throw StateError(
        'GS HEALTH $modeLabel Isolation Error: TEST_SUPABASE_URL must be a valid HTTP(S) Supabase project URL.',
      );
    }

    if (!isDebug) {
      final String? urlRef = _extractSupabaseUrlProjectRef(cleanUrl);
      if (urlRef == null || urlRef != stagingSupabaseProjectRef) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: Profile builds are strictly restricted to staging '
          'Supabase project ($stagingSupabaseProjectRef) at $_stagingSupabaseUrl.',
        );
      }

      final Map<String, dynamic>? claims = _tryDecodeJwtClaims(cleanKey);
      if (claims == null) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: TEST_SUPABASE_ANON_KEY must be a valid JWT '
          'for staging project ($stagingSupabaseProjectRef).',
        );
      }

      final String tokenRef = (claims['ref'] ?? '').toString().trim().toLowerCase();
      final String tokenRole = (claims['role'] ?? '').toString().trim().toLowerCase();
      final String tokenIss = (claims['iss'] ?? '').toString().trim().toLowerCase();

      if (tokenRef.isEmpty) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: TEST_SUPABASE_ANON_KEY JWT is missing required project ref claim.',
        );
      }
      if (tokenRef == productionSupabaseProjectRef) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: Profile builds cannot use a production Supabase anon key '
          '($productionSupabaseProjectRef).',
        );
      }
      if (tokenRef != urlRef || tokenRef != stagingSupabaseProjectRef) {
        throw StateError(
          'GS HEALTH Profile Isolation Error: Mismatched TEST_SUPABASE_URL ($urlRef) and '
          'TEST_SUPABASE_ANON_KEY project ref ($tokenRef); both must match staging project '
          '($stagingSupabaseProjectRef).',
        );
      }
      if (tokenRole != 'anon') {
        throw StateError(
          'GS HEALTH Profile Isolation Error: TEST_SUPABASE_ANON_KEY JWT must have role "anon".',
        );
      }
      if (tokenIss.isNotEmpty && tokenIss != 'supabase') {
        throw StateError(
          'GS HEALTH Profile Isolation Error: TEST_SUPABASE_ANON_KEY JWT has invalid issuer.',
        );
      }
    }

    return (url: cleanUrl, anonKey: cleanKey);
  }

  /// Supabase Cloud URL (strictly staging in staging flavor; fail-closed in debug/profile; locked to production in production release)
  static String get supabaseUrl => isStagingFlavorBuild
      ? _resolveStagingFlavorSupabaseConfig().url
      : resolveSupabaseConfig().url;

  /// Supabase Cloud Anon Key (strictly staging in staging flavor; fail-closed in debug/profile; locked to production in production release)
  static String get supabaseAnonKey => isStagingFlavorBuild
      ? _resolveStagingFlavorSupabaseConfig().anonKey
      : resolveSupabaseConfig().anonKey;

  /// Express Backend API Base URL
  /// - Dedicated `staging` flavor builds ALWAYS use staging Render server
  /// - Public production release builds ALWAYS use live 24/7 production Render server
  /// - Non-release testing builds may override via TEST_API_URL or LOCAL_API_URL
  /// - Debug builds default to localhost:5000 on Web/Desktop and 10.0.2.2:5000 on Android emulator
  static String get baseUrl => debugBaseUrlOverride ??
      (isStagingFlavorBuild ? _resolveStagingFlavorBaseUrl() : resolveBaseUrl());

  // Authentication Endpoints
  static String get login => '$baseUrl/auth/login';
  static String get register => '$baseUrl/auth/register';
  static String get requestOtp => '$baseUrl/auth/otp/request';
  static String get verifyOtp => '$baseUrl/auth/otp/verify';
  static String get realtimeToken => '$baseUrl/auth/realtime-token';
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
