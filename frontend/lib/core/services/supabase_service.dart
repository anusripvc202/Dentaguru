import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

/// Supabase Service — Single OTP Authority for Email Authentication via Resend Custom SMTP
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  /// Initialize Supabase client
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: ApiConstants.supabaseUrl,
        anonKey: ApiConstants.supabaseAnonKey,
        debug: kDebugMode,
      );
      debugPrint('⚡ Supabase Client initialized successfully.');
    } catch (e) {
      debugPrint('⚠️ Supabase Initialization notice: $e');
    }
  }

  /// Get active Supabase client instance
  SupabaseClient get client => Supabase.instance.client;

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

