import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  /// Live 24/7 Render Express Backend API URL (Connected to Supabase PostgreSQL)
  static const String liveBackendUrl = 'https://dentaguru-backend.onrender.com/api/v1';

  /// Supabase Cloud Credentials for Auth & Direct Email OTP
  static const String supabaseUrl = 'https://fommrwxpqzkcktweosgp.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZvbW1yd3hwcXprY2t0d2Vvc2dwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4MTM3MTAsImV4cCI6MjEwMTM4OTcxMH0.VcuNyxIEeUDMGzMf3upGHzDCE_ihdYn0qZY5sjdOD3g';

  /// Express Backend API Base URL
  /// - Web local debug uses http://localhost:5000/api/v1
  /// - Mobile apps (Android/iOS) & Production use live 24/7 Render server
  static String get baseUrl {
    if (kIsWeb && kDebugMode) {
      return 'http://localhost:5000/api/v1';
    }
    return liveBackendUrl;
  }

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
}
