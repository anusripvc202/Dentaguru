import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

/// Supabase Service — Single OTP Authority for Email Authentication via Resend Custom SMTP
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static bool _isInitialized = false;
  static String? _initializedUrl;
  static String? _lastInitError;

  String? _activeRealtimeToken;
  DateTime? _activeRealtimeExpiresAt;
  Timer? _realtimeRefreshTimer;
  int _realtimeSetAuthCount = 0;

  static bool get isInitialized => _isInitialized;
  static String? get initializedUrl => _initializedUrl;
  static String? get lastInitError => _lastInitError;

  String? get activeRealtimeToken => _activeRealtimeToken;
  DateTime? get activeRealtimeExpiresAt => _activeRealtimeExpiresAt;

  @visibleForTesting
  int get realtimeSetAuthCallCount => _realtimeSetAuthCount;

  @visibleForTesting
  static void Function(String token)? debugOnRealtimeSetAuth;

  @visibleForTesting
  static Future<void> Function({
    required String url,
    required String anonKey,
    required bool debug,
  })? debugSupabaseInitializer;

  @visibleForTesting
  static void resetForTesting() {
    _instance.clearRealtimeAuth();
    _instance._realtimeSetAuthCount = 0;
    debugOnRealtimeSetAuth = null;
    _isInitialized = false;
    _initializedUrl = null;
    _lastInitError = null;
    debugSupabaseInitializer = null;
  }

  static Future<void> _defaultSupabaseInit({
    required String url,
    required String anonKey,
    required bool debug,
  }) async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: debug,
    );
  }

  /// Initialize Supabase client with fail-closed debug/testing isolation:
  /// - Release builds always initialize production Supabase.
  /// - Debug/testing builds strictly require TEST_SUPABASE_URL & TEST_SUPABASE_ANON_KEY
  ///   and refuse connecting to production Supabase (`fommrwxpqzkcktweosgp`).
  static Future<void> initialize({
    @visibleForTesting bool? isReleaseOverride,
    @visibleForTesting bool? isStagingFlavorOverride,
    @visibleForTesting bool? isDebugOverride,
    @visibleForTesting bool? isWebOverride,
    @visibleForTesting TargetPlatform? platformOverride,
    @visibleForTesting String? testApiUrlOverride,
    @visibleForTesting String? localApiUrlOverride,
    @visibleForTesting String? testSupabaseUrlOverride,
    @visibleForTesting String? testSupabaseAnonKeyOverride,
  }) async {
    final bool effectiveRelease = isReleaseOverride ?? kReleaseMode;
    final bool effectiveStagingFlavor = isStagingFlavorOverride ?? ApiConstants.isStagingFlavorBuild;
    final bool effectiveDebug = isDebugOverride ?? kDebugMode;

    final ({String url, String anonKey}) config;
    try {
      if (isStagingFlavorOverride == null && ApiConstants.isStagingFlavorBuild) {
        config = (
          url: ApiConstants.supabaseUrl,
          anonKey: ApiConstants.supabaseAnonKey,
        );
      } else {
        config = ApiConstants.resolveSupabaseConfig(
          isRelease: effectiveRelease,
          isStagingFlavor: effectiveStagingFlavor,
          isDebug: effectiveDebug,
          isWeb: isWebOverride ?? kIsWeb,
          platform: platformOverride,
          testApiUrl: testApiUrlOverride ?? const String.fromEnvironment('TEST_API_URL', defaultValue: ''),
          localApiUrl: localApiUrlOverride ?? const String.fromEnvironment('LOCAL_API_URL', defaultValue: ''),
          testSupabaseUrl: testSupabaseUrlOverride ?? const String.fromEnvironment('TEST_SUPABASE_URL', defaultValue: ''),
          testSupabaseAnonKey: testSupabaseAnonKeyOverride ?? const String.fromEnvironment('TEST_SUPABASE_ANON_KEY', defaultValue: ''),
        );
      }
    } on StateError catch (e) {
      _isInitialized = false;
      _initializedUrl = null;
      _lastInitError = e.message;
      debugPrint('❌ ${e.message}');
      rethrow;
    }

    try {
      final initializer = debugSupabaseInitializer ?? _defaultSupabaseInit;
      await initializer(
        url: config.url,
        anonKey: config.anonKey,
        debug: effectiveDebug,
      );
      _isInitialized = true;
      _initializedUrl = config.url;
      _lastInitError = null;
      final host = Uri.tryParse(config.url)?.host ?? 'configured';
      debugPrint('⚡ Supabase Client initialized successfully (host: $host).');
    } catch (e) {
      _isInitialized = false;
      _initializedUrl = null;
      _lastInitError = 'Supabase initialization failed.';
      debugPrint('⚠️ Supabase Initialization notice: $e');
      rethrow;
    }
  }

  /// Get active Supabase client instance
  SupabaseClient get client => Supabase.instance.client;

  /// Safely read the current Supabase client without throwing when Supabase
  /// has not been initialized (e.g., isolated local-backend-only debug runs or tests).
  static SupabaseClient? get safeClient {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Safely read the current Supabase Auth user without throwing when Supabase
  /// has not been initialized (e.g., isolated local-backend-only debug runs or tests).
  static User? get safeCurrentUser {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Authenticates Supabase Realtime WebSockets using the short-lived backend-minted Supabase JWT
  /// (`sub == public.users.id`, `role == authenticated`) and schedules automatic proactive renewal
  /// prior to expiration without logging or exposing raw JWT values.
  Future<bool> authenticateRealtime({
    required String realtimeToken,
    DateTime? expiresAt,
    Future<({String token, DateTime? expiresAt})?> Function()? onRefreshRequired,
  }) async {
    final cleanToken = realtimeToken.trim();
    if (cleanToken.isEmpty) return false;

    _realtimeRefreshTimer?.cancel();
    _activeRealtimeToken = cleanToken;
    _activeRealtimeExpiresAt = expiresAt;
    _realtimeSetAuthCount += 1;
    debugOnRealtimeSetAuth?.call(cleanToken);

    final sb = safeClient;
    if (sb != null) {
      try {
        await sb.realtime.setAuth(cleanToken);
      } catch (e) {
        debugPrint('⚠️ Supabase Realtime setAuth notice: $e');
      }
    }

    if (expiresAt != null && onRefreshRequired != null) {
      final now = DateTime.now();
      final totalRemaining = expiresAt.difference(now);
      // Renew 5 minutes before expiry (or at 75% of remaining lifetime for short test TTLs)
      final Duration refreshDelay = totalRemaining > const Duration(minutes: 10)
          ? totalRemaining - const Duration(minutes: 5)
          : Duration(milliseconds: (totalRemaining.inMilliseconds * 0.75).round().clamp(200, 300000));

      _realtimeRefreshTimer = Timer(refreshDelay, () async {
        try {
          final refreshed = await onRefreshRequired();
          if (refreshed != null && refreshed.token.trim().isNotEmpty) {
            await authenticateRealtime(
              realtimeToken: refreshed.token,
              expiresAt: refreshed.expiresAt,
              onRefreshRequired: onRefreshRequired,
            );
          }
        } catch (e) {
          debugPrint('⚠️ Proactive Realtime JWT refresh notice: $e');
        }
      });
    }

    return true;
  }

  /// Cancels any scheduled Realtime token refresh and clears the active Realtime auth token on logout.
  void clearRealtimeAuth() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _activeRealtimeToken = null;
    _activeRealtimeExpiresAt = null;
    final sb = safeClient;
    if (sb != null) {
      try {
        sb.realtime.setAuth('');
      } catch (_) {}
    }
  }

  /// Dispatch Email OTP code directly via Supabase Auth (Resend Custom SMTP delivery)
  Future<Map<String, dynamic>> sendEmailOtp(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return {'success': false, 'message': 'Please enter a valid email address.'};
    }

    try {
      await client.auth.signInWithOtp(
        email: cleanEmail,
        shouldCreateUser: true,
      );

      debugPrint('📩 Supabase Auth Email OTP requested for: $cleanEmail');
      return {'success': true, 'message': 'OTP sent to your email address.'};
    } on AuthException catch (ae) {
      debugPrint('❌ Supabase Auth OTP Exception [${ae.statusCode}]: ${ae.message}');
      final isRateLimit = ae.statusCode == '429' ||
          ae.code == 'over_email_send_rate_limit' ||
          ae.message.toLowerCase().contains('rate limit') ||
          ae.message.toLowerCase().contains('too many');

      if (isRateLimit) {
        return {'success': false, 'message': 'Too many OTP requests. Please try again later.'};
      }
      return {'success': false, 'message': ae.message};
    } catch (e) {
      debugPrint('❌ Supabase Auth OTP error: $e');
      return {'success': false, 'message': 'Unable to send OTP. Please try again.'};
    }
  }

  /// Verify Email OTP code using Supabase Auth
  Future<Map<String, dynamic>> verifyEmailOtp({required String email, required String token}) async {
    final cleanEmail = email.trim();
    final cleanToken = token.trim();

    if (cleanEmail.isEmpty || cleanToken.isEmpty) {
      return {'success': false, 'message': 'Please enter both email and OTP code.'};
    }

    try {
      final AuthResponse response = await client.auth.verifyOTP(
        type: OtpType.email,
        email: cleanEmail,
        token: cleanToken,
      );

      if (response.user != null || response.session != null) {
        debugPrint('🎉 Supabase Email OTP verified successfully for: $cleanEmail');
        return {'success': true, 'message': 'OTP verified successfully.', 'user': response.user};
      }

      return {'success': false, 'message': 'Invalid or expired OTP.'};
    } on AuthException catch (ae) {
      debugPrint('❌ Supabase Verify OTP Exception: ${ae.message}');
      return {'success': false, 'message': 'Invalid or expired OTP.'};
    } catch (e) {
      debugPrint('❌ Supabase Verify OTP Error: $e');
      return {'success': false, 'message': 'Invalid or expired OTP.'};
    }
  }

  /// Dispatch Mobile SMS OTP code via Supabase Auth
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    final cleanPhone = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) {
      return {'success': false, 'message': 'Please enter a valid mobile number.'};
    }
    final formattedPhone = cleanPhone.startsWith('+') ? cleanPhone : '+91$cleanPhone';

    try {
      await client.auth.signInWithOtp(
        phone: formattedPhone,
        shouldCreateUser: true,
      );

      debugPrint('📩 Supabase Auth Phone SMS OTP requested for: $formattedPhone');
      return {'success': true, 'message': 'OTP sent to mobile number $formattedPhone'};
    } on AuthException catch (ae) {
      debugPrint('❌ Supabase Auth Phone OTP Exception [${ae.statusCode}]: ${ae.message}');
      return {'success': false, 'message': ae.message};
    } catch (e) {
      debugPrint('❌ Supabase Auth Phone OTP error: $e');
      return {'success': false, 'message': 'Unable to send SMS OTP. Please try again.'};
    }
  }

  /// Verify Mobile SMS OTP code using Supabase Auth
  Future<Map<String, dynamic>> verifyPhoneOtp({required String phone, required String token}) async {
    final cleanPhone = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final cleanToken = token.trim();

    if (cleanPhone.isEmpty || cleanToken.isEmpty) {
      return {'success': false, 'message': 'Please enter both mobile number and OTP code.'};
    }
    final formattedPhone = cleanPhone.startsWith('+') ? cleanPhone : '+91$cleanPhone';

    try {
      final AuthResponse response = await client.auth.verifyOTP(
        type: OtpType.sms,
        phone: formattedPhone,
        token: cleanToken,
      );

      if (response.user != null || response.session != null) {
        debugPrint('🎉 Supabase Phone OTP verified successfully for: $formattedPhone');
        return {'success': true, 'message': 'OTP verified successfully.', 'user': response.user};
      }

      return {'success': false, 'message': 'Invalid or expired OTP.'};
    } on AuthException catch (ae) {
      debugPrint('❌ Supabase Verify Phone OTP Exception: ${ae.message}');
      return {'success': false, 'message': 'Invalid or expired OTP.'};
    } catch (e) {
      debugPrint('❌ Supabase Verify Phone OTP Error: $e');
      return {'success': false, 'message': 'Invalid or expired OTP.'};
    }
  }
}

