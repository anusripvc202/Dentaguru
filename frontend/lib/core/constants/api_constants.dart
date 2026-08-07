import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  /// Express Backend API Base URL (Localhost in dev/debug mode, Render in production)
  static String get baseUrl {
    if (kDebugMode) {
      return 'http://localhost:5000/api/v1';
    }
    return 'https://dentaguru.onrender.com/api/v1';
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
