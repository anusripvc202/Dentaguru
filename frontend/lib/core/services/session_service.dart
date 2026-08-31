import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_session.dart';
import 'api_service.dart';
import 'patient_problem_service.dart';

/// Central Service managing secure persistent authentication sessions across the DentaGuru application.
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  static const String _sessionKey = 'dentaguru_secure_auth_session';
  static const String _tokenKey = 'dentaguru_secure_auth_token';
  static const String _roleKey = 'dentaguru_secure_user_role';
  static const String _userIdKey = 'dentaguru_secure_user_id';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  UserSession? _cachedSession;

  /// Get current in-memory cached session
  UserSession? get currentSession => _cachedSession;

  /// Save an authenticated user session securely
  Future<UserSession> saveSession({
    required String token,
    required String role,
    required String userId,
    String? email,
    String? phone,
    String? name,
    Map<String, dynamic>? metadata,
    Duration validDuration = const Duration(days: 30),
  }) async {
    final now = DateTime.now();
    final session = UserSession(
      token: token,
      userId: userId,
      role: role,
      email: email,
      phone: phone,
      name: name,
      createdAt: now,
      expiresAt: now.add(validDuration),
      metadata: metadata ?? {},
    );

    _cachedSession = session;

    try {
      final serialized = session.serialize();
      await _secureStorage.write(key: _sessionKey, value: serialized);
      await _secureStorage.write(key: _tokenKey, value: token);
      await _secureStorage.write(key: _roleKey, value: role);
      await _secureStorage.write(key: _userIdKey, value: userId);

      // Also backup non-sensitive metadata to SharedPreferences for fast offline bootstrap
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dentaguru_last_active_role', role);
      if (email != null && email.isNotEmpty) {
        await prefs.setString('dentaguru_last_active_email', email);
      }
      if (phone != null && phone.isNotEmpty) {
        await prefs.setString('dentaguru_last_active_phone', phone);
      }

      ApiService().setAuthToken(token);
      debugPrint('🔒 Secure session saved for $role (${email ?? phone ?? userId}). Valid for ${validDuration.inDays} days.');
    } catch (e) {
      debugPrint('⚠️ Error saving secure session to storage: $e');
    }

    return session;
  }

  /// Retrieve the current session from secure storage
  Future<UserSession?> getSession() async {
    if (_cachedSession != null) {
      if (_cachedSession!.isExpired) {
        debugPrint('⌛ Cached session expired. Clearing session...');
        await clearSession();
        return null;
      }
      return _cachedSession;
    }

    try {
      final rawJson = await _secureStorage.read(key: _sessionKey);
      final session = UserSession.deserialize(rawJson);

      if (session != null) {
        if (session.isExpired) {
          debugPrint('⌛ Stored session has expired (${session.expiresAt}). Requiring fresh login.');
          await clearSession();
          return null;
        }
        _cachedSession = session;
        ApiService().setAuthToken(session.token);
        return session;
      }
    } catch (e) {
      debugPrint('⚠️ Error reading secure session: $e');
    }

    return null;
  }

  /// Returns true if a valid, unexpired user session exists
  Future<bool> hasValidSession() async {
    final session = await getSession();
    return session != null && !session.isExpired && session.token.isNotEmpty;
  }

  /// Returns active authentication token
  Future<String?> getAuthToken() async {
    final session = await getSession();
    if (session != null) return session.token;
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Restore user session, bind services, and sync live Supabase records
  Future<UserSession?> restoreAppSession() async {
    final session = await getSession();
    if (session == null) {
      debugPrint('ℹ️ No active saved session found on app launch.');
      return null;
    }

    debugPrint('⚡ Restoring session for ${session.displayRole} (${session.name ?? session.email ?? session.phone})');
    ApiService().setAuthToken(session.token);

    final normalizedRole = session.role.trim().toLowerCase();

    // 1. Restore Dentist State
    if (normalizedRole.contains('dentist') || normalizedRole.contains('doctor')) {
      final meta = session.metadata;
      PatientProblemService().registerDoctor(
        id: session.userId,
        name: session.name ?? (session.email?.split('@').first ?? 'Doctor'),
        email: session.email ?? '',
        phone: session.phone ?? '',
        licenseNumber: meta['licenseNumber']?.toString() ?? 'DEN-LIC-REGISTERED',
        specialty: meta['specialty']?.toString() ?? 'General Dentistry',
        clinicName: meta['clinicName']?.toString() ?? '',
        experienceYears: int.tryParse(meta['experienceYears']?.toString() ?? '5') ?? 5,
        languages: meta['languages'] is List ? List<String>.from(meta['languages']) : ['English'],
      );
    }
    // 2. Restore Sub-Admin State
    else if (normalizedRole.contains('sub-admin') || normalizedRole.contains('subadmin')) {
      final meta = session.metadata;
      List<String> perms = [];
      if (meta['permissions'] is List) {
        perms = List<String>.from((meta['permissions'] as List).map((e) => e.toString()));
      }
      PatientProblemService().setSubAdminSession(
        id: session.userId,
        name: session.name ?? 'Sub-Admin',
        email: session.email ?? '',
        phone: session.phone ?? '',
        permissions: perms,
        status: meta['status']?.toString() ?? 'ACTIVE',
      );
    }
    // 3. Restore Patient State
    else if (normalizedRole.contains('patient')) {
      final meta = session.metadata;
      PatientProblemService().updatePatientProfile(
        id: session.userId,
        name: session.name ?? (session.email?.split('@').first ?? 'Patient'),
        email: session.email ?? '',
        phone: session.phone ?? '',
        age: meta['age']?.toString() ?? '',
        gender: meta['gender']?.toString() ?? 'Female',
        bloodGroup: meta['bloodGroup']?.toString() ?? 'O Positive (O+)',
        emergencyContact: meta['emergencyContact']?.toString() ?? session.phone ?? '',
        city: meta['city']?.toString() ?? '',
        pincode: meta['pincode']?.toString() ?? '',
      );
    }

    // Always trigger background sync from Supabase DB to ensure fresh state
    try {
      PatientProblemService().syncAllDataFromApi();
    } catch (e) {
      debugPrint('⚠️ Background data sync error during session restore: $e');
    }

    return session;
  }

  /// Update the current session metadata when user modifies their profile
  Future<void> updateSessionUser({
    String? name,
    String? phone,
    String? email,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    final current = await getSession();
    if (current == null) return;

    final updatedMetadata = Map<String, dynamic>.from(current.metadata);
    if (additionalMetadata != null) {
      updatedMetadata.addAll(additionalMetadata);
    }

    final updated = current.copyWith(
      name: name ?? current.name,
      phone: phone ?? current.phone,
      email: email ?? current.email,
      metadata: updatedMetadata,
    );

    _cachedSession = updated;

    try {
      await _secureStorage.write(key: _sessionKey, value: updated.serialize());
      debugPrint('🔄 Updated persistent session details for ${updated.name ?? updated.email}');
    } catch (e) {
      debugPrint('⚠️ Error updating secure session: $e');
    }
  }

  /// Explicitly clear session on user logout
  Future<void> clearSession() async {
    _cachedSession = null;
    try {
      await _secureStorage.delete(key: _sessionKey);
      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _roleKey);
      await _secureStorage.delete(key: _userIdKey);
    } catch (e) {
      debugPrint('⚠️ Error deleting secure storage session keys: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dentaguru_sub_admin_session');
      await prefs.remove('dentaguru_last_active_role');
    } catch (_) {}

    ApiService().clearAuthToken();
    PatientProblemService().clearSubAdminSession();

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    debugPrint('🚪 User session wiped clean. App returned to unauthenticated state.');
  }
}
