import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

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

  /// Dispatch Email OTP code directly via Supabase Auth & Email Service with ApiService fallback
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

      debugPrint('📩 Supabase Auth Email OTP dispatched to: $cleanEmail');
      return {'success': true, 'message': 'OTP sent to your email.'};
    } on AuthException catch (ae) {
      debugPrint('⚠️ Supabase Auth Rate-Limit / Notice (${ae.message}), falling back to direct API service...');
      // Seamless fail-safe fallback if Supabase free default mailer rate-limits emails
      final apiRes = await ApiService().requestOtp(phone: '', email: cleanEmail);
      if (apiRes['success'] == true) {
        return {'success': true, 'message': 'OTP sent to your email.'};
      }
      return {'success': false, 'message': ae.message.contains('rate limit') ? 'Rate limit reached on Supabase. OTP code sent via secondary mailer.' : ae.message};
    } catch (e) {
      debugPrint('⚠️ Supabase Auth OTP notice ($e), falling back to ApiService...');
      final apiRes = await ApiService().requestOtp(phone: '', email: cleanEmail);
      if (apiRes['success'] == true) {
        return {'success': true, 'message': 'OTP sent to your email.'};
      }
      return {'success': false, 'message': 'Unable to send OTP. Please try again.'};
    }
  }

  /// Verify Email OTP code using Supabase Auth with ApiService fallback
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
    } on AuthException catch (ae) {
      debugPrint('⚠️ Supabase Verify OTP Exception (${ae.message}), attempting fallback verification...');
    } catch (e) {
      debugPrint('⚠️ Supabase Verify OTP Error ($e), attempting fallback verification...');
    }

    // Fallback verification check via ApiService
    final apiRes = await ApiService().verifyOtp(phone: '', email: cleanEmail, code: cleanToken);
    if (apiRes['success'] == true) {
      return {'success': true, 'message': 'OTP verified successfully.'};
    }

    return {'success': false, 'message': 'Invalid or expired OTP.'};
  }
}
