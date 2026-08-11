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

  /// Dispatch Email OTP code directly via Supabase Auth & Email Service
  Future<Map<String, dynamic>> sendEmailOtp(String email) async {
    try {
      final cleanEmail = email.trim();
      if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
        return {'success': false, 'message': 'Please enter a valid email address.'};
      }

      await client.auth.signInWithOtp(
        email: cleanEmail,
        shouldCreateUser: true,
      );

      debugPrint('📩 Supabase Auth Email OTP dispatched to: $cleanEmail');
      return {'success': true, 'message': 'OTP sent to your email.'};
    } on AuthException catch (ae) {
      debugPrint('❌ Supabase Auth OTP Exception: ${ae.message}');
      return {'success': false, 'message': ae.message};
    } catch (e) {
      debugPrint('❌ Supabase Auth OTP error: $e');
      return {'success': false, 'message': 'Unable to send OTP. Please try again.'};
    }
  }

  /// Verify Email OTP code using Supabase Auth
  Future<Map<String, dynamic>> verifyEmailOtp({required String email, required String token}) async {
    try {
      final cleanEmail = email.trim();
      final cleanToken = token.trim();

      if (cleanEmail.isEmpty || cleanToken.isEmpty) {
        return {'success': false, 'message': 'Please enter both email and OTP code.'};
      }

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
      return {'success': false, 'message': ae.message.contains('invalid') || ae.message.contains('expired') ? 'Invalid or expired OTP.' : ae.message};
    } catch (e) {
      debugPrint('❌ Supabase Verify OTP Error: $e');
      return {'success': false, 'message': 'Invalid or expired OTP.'};
    }
  }
}
