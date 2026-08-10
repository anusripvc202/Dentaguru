import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';

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
  'DentaGuru Notifications',   // channel name
  description: 'Appointment alerts and DentaGuru updates',
  importance: Importance.high,
);

/// FirebaseService — manages FCM initialization, token retrieval,
/// and foreground/background notification handling.
class FirebaseService {
  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _secureStorage = FlutterSecureStorage();
  static String? _verificationId;

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

  /// Send Real Verification Email via Google Firebase Auth directly to Gmail inbox
  static Future<bool> sendFirebaseEmailOtp(String email) async {
    try {
      final actionCodeSettings = ActionCodeSettings(
        url: 'https://dentaguru-6d0a0.firebaseapp.com',
        handleCodeInApp: true,
        androidPackageName: 'com.example.dentaguru',
        androidInstallApp: true,
        androidMinimumVersion: '12',
      );

      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );
      debugPrint('📩 Firebase Email Verification dispatched to $email');
      return true;
    } catch (e) {
      debugPrint('⚠️ Firebase Email Auth warning: $e');
      try {
        await _auth.sendPasswordResetEmail(email: email);
        debugPrint('📩 Firebase Action Email dispatched to $email');
        return true;
      } catch (pErr) {
        debugPrint('❌ Firebase Email dispatch failed: $pErr');
        return false;
      }
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
    // 1. Initialize Firebase
    await Firebase.initializeApp();

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
      _showLocalNotification(message);
    });

    // 7. Handle notification tap when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageNavigation);

    // 8. Get & sync FCM token with backend
    await _syncFcmToken();

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

  /// Sync the FCM token to the DentaGuru backend
  static Future<void> _syncFcmToken({String? token}) async {
    try {
      final fcmToken = token ?? await _messaging.getToken();
      if (fcmToken == null) return;

      // Store locally
      await _secureStorage.write(key: 'fcm_token', value: fcmToken);
      debugPrint('📲 FCM Token: $fcmToken');

      // Send to backend if user is authenticated
      final authToken = await _secureStorage.read(key: 'auth_token');
      if (authToken == null) return;

      final baseUrl = ApiConstants.baseUrl;

      await http.put(
        Uri.parse('$baseUrl/auth/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'fcmToken': fcmToken}),
      );
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
          ticker: 'DentaGuru Notification',
          color: const Color(0xFF0B41CD),
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
    );
  }

  /// Handle navigation when user taps a notification
  static void _handleMessageNavigation(RemoteMessage message) {
    final type = message.data['type'] ?? '';
    final appointmentId = message.data['appointmentId'] ?? '';
    debugPrint('📲 Notification tapped — type: $type, id: $appointmentId');
    // TODO: Use go_router to navigate to the relevant screen
    // e.g., appRouter.push('/appointments/$appointmentId');
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('📲 Local notification tapped: ${response.payload}');
  }
}
