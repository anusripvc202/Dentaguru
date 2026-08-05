class ApiConstants {
  ApiConstants._();

  /// Local Express Backend API Base URL
  static const String baseUrl = 'http://localhost:5000/api/v1';

  // Authentication Endpoints
  static const String login = '$baseUrl/auth/login';
  static const String register = '$baseUrl/auth/register';
  static const String requestOtp = '$baseUrl/auth/otp/request';
  static const String verifyOtp = '$baseUrl/auth/otp/verify';
  static const String fcmToken = '$baseUrl/auth/fcm-token';
  static const String biometric = '$baseUrl/auth/biometric';

  // Appointments Endpoints
  static const String appointments = '$baseUrl/appointments';

  // Clinic Profile Endpoints
  static const String clinics = '$baseUrl/clinics';

  // AWS S3 Cloud Storage Endpoints
  static const String upload = '$baseUrl/upload';
  static const String signedUrl = '$baseUrl/upload/signed-url';

  // Chat Endpoints
  static const String chatSend = '$baseUrl/chat/send';

  // Medical Records Endpoints
  static const String records = '$baseUrl/records';
}
