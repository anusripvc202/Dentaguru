import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

import 'analytics_service.dart';
import 'crashlytics_service.dart';
import 'session_service.dart';
import '../routes/app_router.dart';

// ─────────────────────────────────────────────────────────────
// Background message handler (must be a top-level function)
// ─────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📲 FCM Background Message: ${message.messageId}');
}

// ─────────────────────────────────────────────────────────────
// Local notifications plugin for displaying foreground alerts
// ─────────────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'dentaguru_high_importance', // channel id
  'GS HEALTH Notifications',   // channel name
  description: 'Appointment alerts and GS HEALTH updates',
  importance: Importance.high,
);

/// FirebaseService — manages FCM initialization, token retrieval,
/// and foreground/background notification handling.
class FirebaseService {
  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static const String _sessionTokenKey = 'dentaguru_secure_auth_token';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static String? _verificationId;
  static Map<String, dynamic>? _pendingNotificationData;

  /// Optional test hook to intercept resolved navigation routes deterministically.
  @visibleForTesting
  static void Function(String route)? debugNavigateOverride;

  @visibleForTesting
  static Map<String, dynamic>? get pendingNotificationDataForTesting => _pendingNotificationData;

  @visibleForTesting
  static void clearPendingNotificationForTesting() {
    _pendingNotificationData = null;
  }

  @visibleForTesting
  static FlutterSecureStorage get secureStorageForTesting => _secureStorage;

  @visibleForTesting
  static String get authTokenStorageKey => _sessionTokenKey;

  /// Send Real SMS OTP via Firebase Phone Auth
  static Future<void> sendFirebasePhoneOtp(
    String phoneNumber, {
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    try {
      final formattedPhone = phoneNumber.startsWith('+') ? phoneNumber : '+91${phoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';

      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          debugPrint('✅ Firebase Auto Phone Verification Completed');
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('❌ Firebase Phone Auth Error: ${e.message}');
          onError(e.message ?? 'SMS Verification Failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          debugPrint('📩 Firebase SMS OTP Code sent to $formattedPhone');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Send Firebase Email Verification link to user's inbox
  static Future<Map<String, dynamic>> sendFirebaseEmailVerification({
    required String email,
    required String password,
  }) async {
    try {
      User? user = _auth.currentUser;

      if (user == null || user.email != email) {
        try {
          final userCredential = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          user = userCredential.user;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            final userCredential = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            user = userCredential.user;
          } else {
            rethrow;
          }
        }
      }

      if (user != null) {
        await user.sendEmailVerification();
        debugPrint('📩 Firebase Email Verification link dispatched to $email');
        return {
          'success': true,
          'message': 'Verification email sent to your email address.',
        };
      }
      return {
        'success': false,
        'message': 'Unable to send verification email. Please try again.',
      };
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'This email is already in use by another account.';
          break;
        case 'invalid-email':
          msg = 'The email address is invalid.';
          break;
        case 'weak-password':
          msg = 'The password must be at least 6 characters long.';
          break;
        case 'operation-not-allowed':
          msg = 'Email/Password sign-in is disabled in your Firebase Console. Please enable Email/Password under Authentication > Sign-in method in Firebase Console.';
          break;
        case 'too-many-requests':
          msg = 'Too many requests. Please wait a few moments and try again.';
          break;
        default:
          msg = e.message ?? 'Firebase Email Verification failed.';
      }
      return {'success': false, 'message': msg};
    } catch (e) {
      debugPrint('❌ Unexpected Firebase Auth error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Check if the Firebase current user's email is verified
  static Future<bool> checkEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        final refreshedUser = _auth.currentUser;
        debugPrint('🔍 Firebase Email Verified Status: ${refreshedUser?.emailVerified}');
        return refreshedUser?.emailVerified ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ Error reloading Firebase user: $e');
      return false;
    }
  }

  /// Send Password Reset Email via Firebase Auth
  static Future<Map<String, dynamic>> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      debugPrint('📩 Firebase Password Reset Email sent to $email');
      return {
        'success': true,
        'message': 'Password reset link sent to $email. Please check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Password Reset Error: ${e.code} - ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Failed to send password reset email.',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Verify SMS OTP Code via Firebase Phone Auth
  static Future<bool> verifyFirebaseOtp(String smsCode) async {
    if (_verificationId == null) return false;
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user != null;
    } catch (e) {
      debugPrint('❌ Invalid Firebase SMS OTP Code: $e');
      return false;
    }
  }

  /// Call this once in main() before runApp()
  static Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('📲 Firebase Service: Skipping native FCM setup on Web');
      return;
    }
    // 1. Initialize Firebase & Crashlytics
    await Firebase.initializeApp();
    await CrashlyticsService.initialize();

    // 2. Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Request notification permissions (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('📲 FCM Permission: ${settings.authorizationStatus}');

    // 4. Set up Android high-importance notification channel
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 5. Initialize local notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 6. Show local notification for foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📲 FCM Foreground: ${message.notification?.title}');
      AnalyticsService.logNotificationReceived(
        notificationType: message.data['type'] ?? 'general',
        action: 'foreground_received',
      );
      _showLocalNotification(message);
    });

    // 7. Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      AnalyticsService.logNotificationReceived(
        notificationType: message.data['type'] ?? message.data['notificationType'] ?? 'general',
        action: 'tapped_open',
      );
      _handleMessageNavigation(message);
    });

    // 7b. Handle notification tap when app was launched from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      AnalyticsService.logNotificationReceived(
        notificationType: initialMessage.data['type'] ?? initialMessage.data['notificationType'] ?? 'general',
        action: 'terminated_open',
      );
      handleNotificationPayload(initialMessage.data, source: 'terminated_launch');
    }

    // 8. Get & sync FCM token with backend without blocking app cold start
    unawaited(_syncFcmToken());

    // 9. Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('📲 FCM Token refreshed');
      await _syncFcmToken(token: newToken);
    });
  }

  /// Get the current FCM device token
  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Sync FCM device token immediately after user login/session creation.
  /// Safe no-op on Web or when Firebase has not been initialized (e.g. unit tests).
  static Future<void> syncFcmTokenAfterLogin({String? authToken}) async {
    if (kIsWeb) return;
    try {
      if (Firebase.apps.isEmpty) return;
      await _syncFcmToken(authToken: authToken);
    } catch (e) {
      debugPrint('⚠️ Post-login FCM token sync skipped: $e');
    }
  }

  /// Sync the FCM token to the DentaGuru backend
  static Future<void> _syncFcmToken({String? token, String? authToken}) async {
    try {
      if (kIsWeb || Firebase.apps.isEmpty) return;
      final fcmToken = token ?? await _messaging.getToken();
      if (fcmToken == null || fcmToken.trim().isEmpty) return;

      // Store locally in encrypted shared preferences
      await _secureStorage.write(key: 'fcm_token', value: fcmToken);
      debugPrint('📲 FCM Token synced locally');

      // Resolve authenticated JWT from explicit param, SessionService, or aligned secure storage key
      String? resolvedAuthToken = authToken?.trim();
      if (resolvedAuthToken == null || resolvedAuthToken.isEmpty) {
        resolvedAuthToken = SessionService().currentSession?.token.trim();
      }
      if (resolvedAuthToken == null || resolvedAuthToken.isEmpty) {
        resolvedAuthToken =
            (await _secureStorage.read(key: _sessionTokenKey))?.trim();
      }
      if (resolvedAuthToken == null || resolvedAuthToken.isEmpty) {
        resolvedAuthToken = (await _secureStorage.read(key: 'auth_token'))?.trim();
      }
      if (resolvedAuthToken == null || resolvedAuthToken.isEmpty) return;

      final baseUrl = ApiConstants.baseUrl;

      await http.put(
        Uri.parse('$baseUrl/auth/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $resolvedAuthToken',
        },
        body: jsonEncode({'fcmToken': fcmToken}),
      ).timeout(const Duration(seconds: 35));
      debugPrint('✅ FCM token synced to backend');
    } catch (e) {
      debugPrint('❌ FCM token sync error: $e');
    }
  }

  /// Show a visible notification banner for foreground FCM messages
  static void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    final android = message.notification?.android;
    if (notification == null) return;

    final payloadJson = message.data.isNotEmpty ? jsonEncode(message.data) : null;

    _localNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'GS HEALTH Notification',
          color: const Color(0xFF012A58),
          icon: android?.smallIcon ?? '@mipmap/ic_launcher',
          channelShowBadge: true,
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payloadJson,
    );
  }

  /// Resolves the target GoRouter path from an FCM/local notification data payload.
  static String resolveRouteFromNotificationData(
    Map<String, dynamic> data, {
    String? userRole,
  }) {
    final rawType = (data['notificationType'] ?? data['type'] ?? '').toString().trim().toLowerCase();
    final roleLower = (userRole ?? SessionService().currentSession?.role ?? 'Patient').trim().toLowerCase();
    final isDoctor = roleLower == 'dentist' || roleLower == 'doctor';
    final isClinic = roleLower == 'clinic' || roleLower == 'clinic_admin';
    final isAdmin = roleLower.contains('admin');

    // Early slot release / direct booking deep-link -> open Patient booking dialog with preselected doctor/date/slot
    if (rawType == 'early_slot_released' ||
        rawType == 'earlier_slot_available' ||
        rawType == 'slot_released' ||
        rawType == 'booking') {
      final qp = <String, String>{
        'tab': '0',
        if ((data['doctorId'] ?? data['dentistId'] ?? '').toString().trim().isNotEmpty)
          'openBookingDoctorId': (data['doctorId'] ?? data['dentistId']).toString().trim(),
        if ((data['appointmentDate'] ?? data['date'] ?? '').toString().trim().isNotEmpty)
          'bookingDate': (data['appointmentDate'] ?? data['date']).toString().trim(),
        if ((data['startTime'] ?? data['timeSlot'] ?? '').toString().trim().isNotEmpty)
          'bookingSlot': (data['startTime'] ?? data['timeSlot']).toString().trim(),
        if ((data['consultationType'] ?? data['consultationMode'] ?? '').toString().trim().isNotEmpty)
          'bookingMode': (data['consultationType'] ?? data['consultationMode']).toString().trim(),
      };
      return Uri(path: '/patient', queryParameters: qp).toString();
    }

    if (rawType.contains('prescription') || rawType == 'consultation_completed') {
      if (isDoctor) return '/dentist?tab=4';
      return '/patient?tab=3';
    }

    if (rawType.contains('referral')) {
      if (isDoctor) return '/dentist?tab=2';
      if (isAdmin) return '/admin/referrals';
      if (isClinic) return '/clinic';
      return '/patient?tab=0';
    }

    if (rawType.contains('appointment') || rawType.contains('doctor_ready') || rawType.contains('delay')) {
      if (isDoctor) return '/dentist?tab=0';
      if (isClinic) return '/clinic';
      if (isAdmin) return '/admin';
      return '/patient?tab=2';
    }

    if (isDoctor) return '/dentist';
    if (isClinic) return '/clinic';
    if (isAdmin) return roleLower.contains('sub') ? '/sub-admin' : '/admin';
    return '/patient';
  }

  /// Handles any notification tap (foreground local banner, background resume, or terminated app launch).
  static void handleNotificationPayload(
    Map<String, dynamic> data, {
    String source = 'unknown',
    String? userRoleOverride,
  }) {
    debugPrint('📲 Notification tapped ($source) — payload: $data');
    final session = SessionService().currentSession;
    final hasSession = session != null && !session.isExpired && session.token.trim().isNotEmpty;

    if (!hasSession && debugNavigateOverride == null) {
      // App launched from terminated state before session restore finished; defer until dashboard mounts
      _pendingNotificationData = Map<String, dynamic>.from(data);
      return;
    }

    final targetRoute = resolveRouteFromNotificationData(
      data,
      userRole: userRoleOverride ?? session?.role,
    );
    _pendingNotificationData = null;

    if (debugNavigateOverride != null) {
      debugNavigateOverride!(targetRoute);
      return;
    }

    try {
      appRouter.go(targetRoute);
    } catch (e) {
      debugPrint('⚠️ Notification navigation deferred: $e');
      _pendingNotificationData = Map<String, dynamic>.from(data);
    }
  }

  /// Replays any notification tap that arrived during terminated-app startup once the user session is active.
  static bool consumePendingNotificationNavigation() {
    if (_pendingNotificationData == null) return false;
    final session = SessionService().currentSession;
    final hasSession = session != null && !session.isExpired && session.token.trim().isNotEmpty;
    if (!hasSession && debugNavigateOverride == null) return false;

    final pending = Map<String, dynamic>.from(_pendingNotificationData!);
    _pendingNotificationData = null;
    handleNotificationPayload(pending, source: 'deferred_terminated_open');
    return true;
  }

  /// Handle navigation when user taps a background FCM notification
  static void _handleMessageNavigation(RemoteMessage message) {
    handleNotificationPayload(message.data, source: 'background_tap');
  }

  /// Handle navigation when user taps a foreground local notification banner
  static void _onNotificationTap(NotificationResponse response) {
    handleLocalNotificationPayloadString(response.payload);
  }

  /// Parses raw local notification payload JSON string and routes cleanly.
  static void handleLocalNotificationPayloadString(String? rawPayload) {
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      handleNotificationPayload(const <String, dynamic>{}, source: 'foreground_tap');
      return;
    }
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        handleNotificationPayload(
          Map<String, dynamic>.from(decoded),
          source: 'foreground_tap',
        );
        return;
      }
    } catch (_) {}
    handleNotificationPayload(const <String, dynamic>{}, source: 'foreground_tap');
  }
}
