import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// AnalyticsService — Centralized Firebase Analytics tracking service
/// Tracks user engagement & events without logging sensitive patient/medical data.
class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  /// 1. App Open Event
  static Future<void> logAppOpen() async {
    try {
      await _analytics.logAppOpen();
      debugPrint('📊 Firebase Analytics: logAppOpen');
    } catch (e) {
      debugPrint('⚠️ Analytics logAppOpen error: $e');
    }
  }

  /// 2. Login Event
  static Future<void> logLogin({
    required String method,
    required String role,
  }) async {
    try {
      await _analytics.logLogin(
        loginMethod: method,
        parameters: {
          'user_role': role,
        },
      );
      debugPrint('📊 Firebase Analytics: logLogin ($method, $role)');
    } catch (e) {
      debugPrint('⚠️ Analytics logLogin error: $e');
    }
  }

  /// 3. Registration Event
  static Future<void> logRegistration({
    required String role,
    String method = 'Email_Password',
  }) async {
    try {
      await _analytics.logSignUp(
        signUpMethod: method,
        parameters: {
          'user_role': role,
        },
      );
      debugPrint('📊 Firebase Analytics: logRegistration ($role)');
    } catch (e) {
      debugPrint('⚠️ Analytics logRegistration error: $e');
    }
  }

  /// 4. OTP / Identity Verification Event
  static Future<void> logOtpVerification({
    required String status,
    required String method,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'otp_verification',
        parameters: {
          'status': status,
          'method': method,
        },
      );
      debugPrint('📊 Firebase Analytics: logOtpVerification ($status, $method)');
    } catch (e) {
      debugPrint('⚠️ Analytics logOtpVerification error: $e');
    }
  }

  /// 5. Appointment Booking Event
  static Future<void> logAppointmentBooking({
    required String doctorId,
    String? serviceName,
    String? clinicId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'appointment_booked',
        parameters: {
          'doctor_id': doctorId,
          if (serviceName != null) 'service_type': serviceName,
          if (clinicId != null) 'clinic_id': clinicId,
        },
      );
      debugPrint('📊 Firebase Analytics: logAppointmentBooking (Doctor: $doctorId)');
    } catch (e) {
      debugPrint('⚠️ Analytics logAppointmentBooking error: $e');
    }
  }

  /// 6. Doctor Selection Event
  static Future<void> logDoctorSelection({
    required String doctorId,
    String? specialty,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'doctor_selected',
        parameters: {
          'doctor_id': doctorId,
          if (specialty != null) 'specialty': specialty,
        },
      );
      debugPrint('📊 Firebase Analytics: logDoctorSelection (Doctor: $doctorId)');
    } catch (e) {
      debugPrint('⚠️ Analytics logDoctorSelection error: $e');
    }
  }

  /// 7. Consultation Completed Event
  static Future<void> logConsultationCompleted({
    required String appointmentId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'consultation_completed',
        parameters: {
          'appointment_id': appointmentId,
        },
      );
      debugPrint('📊 Firebase Analytics: logConsultationCompleted ($appointmentId)');
    } catch (e) {
      debugPrint('⚠️ Analytics logConsultationCompleted error: $e');
    }
  }

  /// 8. Push Notification Interaction Event
  static Future<void> logNotificationReceived({
    required String notificationType,
    String action = 'received',
  }) async {
    try {
      await _analytics.logEvent(
        name: 'notification_interaction',
        parameters: {
          'notification_type': notificationType,
          'action': action,
        },
      );
      debugPrint('📊 Firebase Analytics: logNotificationReceived ($notificationType)');
    } catch (e) {
      debugPrint('⚠️ Analytics logNotificationReceived error: $e');
    }
  }

  /// Set User ID for Analytics (Non-sensitive ID)
  static Future<void> setUserId(String userId) async {
    try {
      await _analytics.setUserId(id: userId);
      debugPrint('📊 Firebase Analytics: setUserId ($userId)');
    } catch (e) {
      debugPrint('⚠️ Analytics setUserId error: $e');
    }
  }
}
