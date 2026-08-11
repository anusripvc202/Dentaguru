import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// CrashlyticsService — Centralized error and crash reporting service
/// Captures fatal crashes, non-fatal errors, and diagnostic logs safely without storing PII/PHI.
class CrashlyticsService {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  /// Initialize Crashlytics Error Handlers
  static Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('💥 Crashlytics: Skipping setup on Web platform');
      return;
    }

    try {
      // Automatic error collection enablement
      await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Pass all uncaught Flutter framework errors to Crashlytics
      FlutterError.onError = (FlutterErrorDetails details) {
        debugPrint('💥 Crashlytics Caught Flutter Error: ${details.exceptionAsString()}');
        _crashlytics.recordFlutterFatalError(details);
      };

      // Pass all uncaught asynchronous errors to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('💥 Crashlytics Caught Platform Error: $error');
        _crashlytics.recordError(error, stack, fatal: true);
        return true;
      };

      debugPrint('✅ Firebase Crashlytics initialized successfully');
    } catch (e) {
      debugPrint('⚠️ Crashlytics initialization warning: $e');
    }
  }

  /// Record Non-Fatal Exception
  static Future<void> recordNonFatalError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (kIsWeb) return;
    try {
      await _crashlytics.recordError(
        exception,
        stack,
        reason: reason,
        fatal: fatal,
      );
      debugPrint('💥 Crashlytics Non-Fatal Error Recorded: $reason ($exception)');
    } catch (e) {
      debugPrint('⚠️ Crashlytics recordNonFatalError warning: $e');
    }
  }

  /// Add Custom Log Message to Crash Context
  static Future<void> log(String message) async {
    if (kIsWeb) return;
    try {
      await _crashlytics.log(message);
    } catch (e) {
      debugPrint('⚠️ Crashlytics log warning: $e');
    }
  }

  /// Set Custom Key-Value Diagnostic Attributes
  static Future<void> setCustomKey(String key, Object value) async {
    if (kIsWeb) return;
    try {
      await _crashlytics.setCustomKey(key, value);
    } catch (e) {
      debugPrint('⚠️ Crashlytics setCustomKey warning: $e');
    }
  }

  /// Set Non-Sensitive User Identifier
  static Future<void> setUserIdentifier(String userId) async {
    if (kIsWeb) return;
    try {
      await _crashlytics.setUserIdentifier(userId);
    } catch (e) {
      debugPrint('⚠️ Crashlytics setUserIdentifier warning: $e');
    }
  }
}
