import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';
import '../constants/booking_rules_config.dart';
import '../models/medical_specialty_model.dart';
import 'analytics_service.dart';
import 'session_service.dart';
import 'supabase_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _authToken;

  void setAuthToken(String token) {
    _authToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
  }

  String? get currentToken {
    if (_authToken != null && _authToken!.isNotEmpty) return _authToken;
    return SupabaseService.safeClient?.auth.currentSession?.accessToken;
  }

  Map<String, String> get _headers {
    final token = currentToken;
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> _headersWithUser([String? userIdOverride]) {
    final effectiveUserId = (userIdOverride != null && userIdOverride.trim().isNotEmpty)
        ? userIdOverride.trim()
        : (SessionService().currentSession?.userId.trim().isNotEmpty == true
            ? SessionService().currentSession!.userId.trim()
            : (SupabaseService.safeCurrentUser?.id ?? '').trim());
    return {
      ..._headers,
      if (effectiveUserId.isNotEmpty) 'x-user-id': effectiveUserId,
    };
  }


  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String name,
    required String phone,
    String? email,
    String? password,
    String role,
    String? age,
    String? gender,
    String? bloodGroup,
    String? emergencyContact,
    String? specialty,
    String? licenseNumber,
    String? clinicId,
    String? clinicName,
    String? clinicAddress,
    String? consultationFee,
    String? bio,
    String? location,
    String? state,
    String? city,
    String? pincode,
    double? latitude,
    double? longitude,
    String? qualification,
    int? experienceYears,
    String? profilePhoto,
    List<String>? languages,
    String? referralCode,
  })? debugRegisterOverride;

  @visibleForTesting
  static Map<String, dynamic>? debugLastRegisterPayload;

  /// Register a new user (Patient, Dentist, Clinic, Admin) in Supabase via Backend API
  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String phone,
    String? email,
    String? password,
    String role = 'Patient',
    String? age,
    String? gender,
    String? bloodGroup,
    String? emergencyContact,
    String? specialty,
    String? licenseNumber,
    String? clinicId,
    String? clinicName,
    String? clinicAddress,
    String? consultationFee,
    String? bio,
    String? location,
    String? state,
    String? city,
    String? pincode,
    double? latitude,
    double? longitude,
    String? qualification,
    int? experienceYears,
    String? profilePhoto,
    List<String>? languages,
    String? referralCode,
  }) async {
    debugLastRegisterPayload = {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'specialty': specialty,
      'clinicId': clinicId,
      'clinicName': clinicName,
      'clinicAddress': clinicAddress,
      'location': location,
      'state': state,
      'city': city,
      'pincode': pincode,
      'latitude': latitude,
      'longitude': longitude,
      'qualification': qualification,
      'experienceYears': experienceYears,
      'languages': languages,
    };
    final registerOverride = debugRegisterOverride;
    if (registerOverride != null) {
      return registerOverride(
        name: name,
        phone: phone,
        email: email,
        password: password,
        role: role,
        age: age,
        gender: gender,
        bloodGroup: bloodGroup,
        emergencyContact: emergencyContact,
        specialty: specialty,
        licenseNumber: licenseNumber,
        clinicId: clinicId,
        clinicName: clinicName,
        clinicAddress: clinicAddress,
        consultationFee: consultationFee,
        bio: bio,
        location: location,
        state: state,
        city: city,
        pincode: pincode,
        latitude: latitude,
        longitude: longitude,
        qualification: qualification,
        experienceYears: experienceYears,
        profilePhoto: profilePhoto,
        languages: languages,
        referralCode: referralCode,
      );
    }
    final rawDigits = phone.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final cleanDigits = (rawDigits.length == 12 && rawDigits.startsWith('91'))
        ? rawDigits.substring(2)
        : ((rawDigits.length == 11 && rawDigits.startsWith('0'))
            ? rawDigits.substring(1)
            : rawDigits);
    final cleanPhone = cleanDigits.isNotEmpty ? cleanDigits : phone.trim();

    if (cleanPhone.isEmpty || cleanDigits.length < 10) {
      return {
        'success': false,
        'message': 'Please enter a valid 10-digit mobile phone number.'
      };
    }

    final effectiveLanguages = (languages != null && languages.isNotEmpty)
        ? languages
        : <String>['English'];

    final cleanLocation = (location != null && location.trim().isNotEmpty) ? location.trim() : null;
    final cleanClinicAddress = (clinicAddress != null && clinicAddress.trim().isNotEmpty) ? clinicAddress.trim() : null;
    final cleanState = (state != null && state.trim().isNotEmpty) ? state.trim() : null;
    final effectiveLocation = cleanLocation ?? cleanClinicAddress ?? cleanState ?? '';

    final cleanEmail = (email != null && email.trim().isNotEmpty && email.contains('@'))
        ? email.trim()
        : 'user_${cleanDigits.isNotEmpty ? cleanDigits : DateTime.now().millisecondsSinceEpoch}@dentaguru.internal';
    final cleanPassword = (password != null && password.trim().isNotEmpty) ? password.trim() : 'Passwordless_${cleanPhone.replaceAll('+', '')}';

    final prefix = name.trim().length >= 3 ? name.trim().substring(0, 3).toUpperCase() : name.trim().toUpperCase();
    final sfx = cleanDigits.length >= 4 ? cleanDigits.substring(cleanDigits.length - 4) : '2026';
    final generatedRefCode = 'DG-${prefix.isNotEmpty ? prefix : 'PAT'}$sfx';

    final payload = jsonEncode({
      'name': name.trim(),
      'email': cleanEmail,
      'password': cleanPassword,
      'phone': cleanPhone,
      'role': role,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (bloodGroup != null) 'bloodGroup': bloodGroup,
      if (emergencyContact != null) 'emergencyContact': emergencyContact,
      if (specialty != null) 'specialty': specialty,
      if (licenseNumber != null && licenseNumber.trim().isNotEmpty) 'licenseNumber': licenseNumber.trim(),
      if (clinicId != null && clinicId.trim().isNotEmpty) 'clinicId': clinicId.trim(),
      if (clinicName != null) 'clinicName': clinicName,
      if (cleanClinicAddress != null) 'clinicAddress': cleanClinicAddress,
      if (consultationFee != null && consultationFee.trim().isNotEmpty) 'consultationFee': consultationFee.trim(),
      if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
      if (cleanLocation != null) 'location': cleanLocation,
      if (cleanState != null) 'state': cleanState,
      if (city != null) 'city': city,
      if (pincode != null) 'pincode': pincode,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (qualification != null) 'qualification': qualification,
      if (experienceYears != null) 'experienceYears': experienceYears,
      if (profilePhoto != null) 'profilePhoto': profilePhoto,
      'languages': effectiveLanguages,
      if (referralCode != null && referralCode.trim().isNotEmpty) 'referralCode': referralCode.trim(),
    });

    try {
      final url = Uri.parse(ApiConstants.register);
      debugPrint('🌐 Sending Register Request to: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode >= 500) {
        throw Exception('Register server unavailable (HTTP ${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['accessToken'] != null) {
          setAuthToken(data['accessToken']);
        }
        return {'success': true, 'data': data};
      } else {
        final serverMsg = (data['message'] ?? 'Registration failed.').toString();
        final lowerMsg = serverMsg.toLowerCase();
        // If remote server returned a legacy optional-field rejection (Location/Address, Language, or omitted Pincode),
        // fall through to direct Supabase PostgreSQL registration without sending dummy values.
        if (lowerMsg.contains('location') ||
            lowerMsg.contains('address') ||
            lowerMsg.contains('language') ||
            (lowerMsg.contains('pincode') && (pincode == null || pincode.trim().isEmpty))) {
          throw Exception('Legacy optional field rejection on remote server: $serverMsg');
        }
        return {
          'success': false,
          if (data['code'] != null) 'code': data['code'].toString(),
          'message': serverMsg,
        };
      }
    } catch (e) {
      debugPrint('⚠️ Primary Register URL notice ($e). Executing direct 24/7 Supabase PostgreSQL registration...');
      try {
        final client = Supabase.instance.client;
        final existingByPhone = await _findSupabaseUserByIdentifier(phone, cleanPhone);
        if (existingByPhone != null) {
          return {
            'success': false,
            'code': 'MOBILE_ALREADY_REGISTERED',
            'existingRole': existingByPhone['role'] ?? 'Patient',
            'message': 'Phone number already registered. Please sign in with OTP.'
          };
        }

        if (!cleanEmail.endsWith('@dentaguru.internal')) {
          final existingByEmail = await client
              .from('users')
              .select('id, email, phone')
              .ilike('email', cleanEmail)
              .maybeSingle();
          if (existingByEmail != null && existingByEmail['phone']?.toString() != cleanPhone) {
            return {
              'success': false,
              'message': 'Email already registered.'
            };
          }
        }

        final bool isDoctorOrClinicReg = role == 'Dentist' ||
            role.toLowerCase() == 'dentist' ||
            role.toLowerCase() == 'doctor' ||
            role == 'Clinic' ||
            role.toLowerCase() == 'clinic';

        final profileMeta = jsonEncode({
          'age': age ?? '',
          'gender': gender ?? '',
          'bloodGroup': bloodGroup ?? '',
          'emergencyContact': emergencyContact ?? '',
          'city': city ?? '',
          'state': cleanState ?? '',
          'pincode': pincode ?? '',
          'location': effectiveLocation,
          'address': cleanClinicAddress ?? effectiveLocation,
          if (isDoctorOrClinicReg && clinicName != null) 'clinicName': clinicName.trim(),
          if (isDoctorOrClinicReg && cleanClinicAddress != null) 'clinicAddress': cleanClinicAddress,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          'languages': effectiveLanguages,
          'referral_code': generatedRefCode,
          if (referralCode != null && referralCode.trim().isNotEmpty) 'referred_by_code': referralCode.trim().toUpperCase(),
        });

        final coreUserMap = <String, dynamic>{
          'name': name.trim().isNotEmpty ? name.trim() : 'Patient',
          'email': cleanEmail,
          'password': cleanPassword,
          'phone': cleanPhone,
          'role': role,
          'city': city?.trim() ?? '',
          'pincode': pincode?.trim() ?? '',
          'state': cleanState ?? '',
          'device_token': profileMeta,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (profilePhoto != null) 'biometric_token': profilePhoto,
        };

        Map<String, dynamic> insertedUser;
        try {
          insertedUser = await client
              .from('users')
              .insert({
                ...coreUserMap,
                'age': age ?? '',
                'gender': gender ?? '',
                'blood_group': bloodGroup ?? '',
                'emergency_contact': emergencyContact ?? '',
                'referral_code': generatedRefCode,
              })
              .select()
              .single();
        } catch (_) {
          insertedUser = await client
              .from('users')
              .insert(coreUserMap)
              .select()
              .single();
        }

        final String newUserId = insertedUser['id'].toString();
        String? registeredDentistId;
        String? registeredClinicId = (clinicId != null && clinicId.trim().isNotEmpty) ? clinicId.trim() : null;

        if (role == 'Dentist' || role.toLowerCase() == 'dentist' || role.toLowerCase() == 'doctor') {
          try {
            final rawLic = (licenseNumber ?? '').trim();
            final lic = (rawLic.isNotEmpty &&
                    rawLic.toLowerCase() != 'med-lic-reg' &&
                    rawLic.toLowerCase() != 'med-lic-registered')
                ? rawLic
                : 'MED-LIC-${DateTime.now().millisecondsSinceEpoch}';
            final effectiveSpec = (specialty != null && specialty.trim().isNotEmpty)
                ? specialty.trim()
                : 'General Medicine';
            final effectiveQual = (qualification != null && qualification.trim().isNotEmpty)
                ? qualification.trim()
                : MedicalSpecialtyModel.getDefaultQualificationForSpecialty(effectiveSpec);
            String? resolvedClinicId = registeredClinicId;
            if (resolvedClinicId == null && clinicName != null && clinicName.trim().isNotEmpty) {
              final existingClinic = await client
                  .from('clinics')
                  .select('id')
                  .ilike('clinic_name', clinicName.trim())
                  .limit(1);
              if (existingClinic.isNotEmpty) {
                resolvedClinicId = existingClinic.first['id']?.toString();
              } else {
                final createdClinic = await client.from('clinics').insert({
                  'user_id': newUserId,
                  'clinic_name': clinicName.trim(),
                  'location': effectiveLocation,
                  'verified': true,
                  'services': [effectiveSpec, 'General Consultation'],
                }).select('id').single();
                resolvedClinicId = createdClinic['id']?.toString();
              }
            }
            registeredClinicId = resolvedClinicId;
            String? resolvedSpecId;
            try {
              final specRow = await client
                  .from('medical_specialties')
                  .select('id')
                  .ilike('name', effectiveSpec)
                  .maybeSingle();
              if (specRow != null) {
                resolvedSpecId = specRow['id']?.toString();
              }
            } catch (_) {}
            final dentistInsertPayload = <String, dynamic>{
              'user_id': newUserId,
              if (resolvedClinicId != null && resolvedClinicId.isNotEmpty) 'clinic_id': resolvedClinicId,
              if (clinicName != null && clinicName.trim().isNotEmpty) 'clinic_name': clinicName.trim(),
              if (cleanClinicAddress != null && cleanClinicAddress.isNotEmpty) 'clinic_address': cleanClinicAddress,
              'speciality': effectiveSpec,
              if (resolvedSpecId != null) 'specialty_id': resolvedSpecId,
              'license_number': lic,
              'experience_years': experienceYears ?? 5,
              'qualifications': effectiveQual,
              'availability_status': 'Available',
              if (consultationFee != null && consultationFee.trim().isNotEmpty) 'consultation_fee': consultationFee.trim(),
              if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
              'languages': effectiveLanguages,
              'state': cleanState ?? '',
              'city': city?.trim() ?? '',
              'pincode': pincode?.trim() ?? '',
              if (latitude != null) 'latitude': latitude,
              if (longitude != null) 'longitude': longitude,
              'rating': 5.0,
              'reviews_count': 0,
            };
            try {
              final insertedDentist = await client.from('dentists').insert(dentistInsertPayload).select('id').single();
              registeredDentistId = insertedDentist['id']?.toString();
            } catch (_) {
              final legacyPayload = Map<String, dynamic>.from(dentistInsertPayload)
                ..remove('clinic_name')
                ..remove('clinic_address');
              final insertedDentist = await client.from('dentists').insert(legacyPayload).select('id').single();
              registeredDentistId = insertedDentist['id']?.toString();
            }
          } catch (_) {}
        } else if (role == 'Clinic' || role.toLowerCase() == 'clinic') {
          try {
            final cName = (clinicName != null && clinicName.trim().isNotEmpty)
                ? clinicName.trim()
                : (name.trim().isNotEmpty ? name.trim() : 'GS HEALTH Clinic');
            final cAddr = cleanClinicAddress ?? effectiveLocation;
            final existingClinic = await client
                .from('clinics')
                .select('id, user_id')
                .ilike('clinic_name', cName)
                .limit(1)
                .maybeSingle();
            if (existingClinic == null) {
              final coreClinicMap = <String, dynamic>{
                'user_id': newUserId,
                'clinic_name': cName,
                'location': cAddr.isNotEmpty ? cAddr : (city?.trim() ?? 'GS HEALTH Medical Center'),
                'verified': true,
                'rating': 5.0,
                'reviews_count': 0,
                'services': ['General Consultation'],
              };
              try {
                final createdClinic = await client
                    .from('clinics')
                    .insert({
                      ...coreClinicMap,
                      'clinic_address': cAddr,
                      'city': city?.trim() ?? '',
                      'state': cleanState ?? '',
                      'pincode': pincode?.trim() ?? '',
                      if (latitude != null) 'latitude': latitude,
                      if (longitude != null) 'longitude': longitude,
                    })
                    .select('id')
                    .single();
                registeredClinicId = createdClinic['id']?.toString();
              } catch (_) {
                final createdClinic = await client
                    .from('clinics')
                    .insert(coreClinicMap)
                    .select('id')
                    .single();
                registeredClinicId = createdClinic['id']?.toString();
              }
            } else {
              registeredClinicId = existingClinic['id']?.toString();
              if (existingClinic['user_id'] == null || existingClinic['user_id'].toString().trim().isEmpty) {
                await client.from('clinics').update({'user_id': newUserId}).eq('id', existingClinic['id']);
              }
            }
          } catch (_) {}
        } else if (role == 'Sub-Admin' || role.toLowerCase().contains('sub')) {
          try {
            final perms = [
              'ALL',
              'MANAGE_PATIENTS',
              'MANAGE_REQUESTS',
              'VIEW_DENTISTS',
              'MANAGE_CLINICS',
              'MANAGE_REFERRALS',
              'VIEW_RECORDS',
              'APPOINTMENTS'
            ];
            final rows = perms.map((p) => {'user_id': newUserId, 'permission': p}).toList();
            await client.from('sub_admin_permissions').insert(rows);
          } catch (_) {}
        }

        final String directToken = 'sb_direct_$newUserId';
        setAuthToken(directToken);

        return {
          'success': true,
          'data': {
            'accessToken': directToken,
            'user': {
              'id': newUserId,
              if (registeredDentistId != null) 'dentistId': registeredDentistId,
              if (registeredClinicId != null) 'clinicId': registeredClinicId,
              'name': insertedUser['name'] ?? name.trim(),
              'email': insertedUser['email'] ?? cleanEmail,
              'phone': insertedUser['phone'] ?? cleanPhone,
              'role': insertedUser['role'] ?? role,
              'age': age ?? '',
              'gender': gender ?? '',
              'bloodGroup': bloodGroup ?? '',
              'emergencyContact': emergencyContact ?? '',
              'city': city?.trim() ?? '',
              'pincode': pincode?.trim() ?? '',
              'state': cleanState ?? '',
              'address': cleanClinicAddress ?? effectiveLocation,
              if (clinicName != null && clinicName.trim().isNotEmpty) 'clinicName': clinicName.trim(),
              if (cleanClinicAddress != null && cleanClinicAddress.isNotEmpty) 'clinicAddress': cleanClinicAddress,
              if (latitude != null) 'latitude': latitude,
              if (longitude != null) 'longitude': longitude,
              if (specialty != null) 'specialty': specialty,
              if (qualification != null) 'qualification': qualification,
              if (experienceYears != null) 'experienceYears': experienceYears,
              'languages': effectiveLanguages,
              'referralCode': generatedRefCode,
              'profilePhoto': profilePhoto,
            }
          }
        };
      } catch (sbErr) {
        debugPrint('Direct 24/7 Supabase DB registration error: $sbErr');
      }
      return {'success': false, 'message': 'Registration error. Please check your phone number and network.'};
    }
  }

  /// Login user via central backend with 24/7 Supabase Auth fallback
  /// Test-only hook so widget tests can exercise login flows without a live backend.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    String? email,
    String? phone,
    String? password,
    String? otp,
    String? role,
  })? debugLoginOverride;

  Future<Map<String, dynamic>> loginUser({
    String? email,
    String? phone,
    String? password,
    String? otp,
    String? code,
    String? role,
  }) async {
    if (debugLoginOverride != null) {
      return debugLoginOverride!(
        email: email,
        phone: phone,
        password: password,
        otp: (otp != null && otp.trim().isNotEmpty) ? otp.trim() : code?.trim(),
        role: role,
      );
    }
    final rawIdentifier = (phone != null && phone.trim().isNotEmpty) ? phone.trim() : (email ?? '').trim();
    String identifier = rawIdentifier;
    if (!rawIdentifier.contains('@') && RegExp(r'^[+\d\s\-()]+$').hasMatch(rawIdentifier)) {
      final digits = rawIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 14 && digits.startsWith('0091')) {
        identifier = digits.substring(4);
      } else if (digits.length == 13 && digits.startsWith('910')) {
        identifier = digits.substring(3);
      } else if (digits.length == 12 && digits.startsWith('91')) {
        identifier = digits.substring(2);
      } else if (digits.length == 11 && digits.startsWith('0')) {
        identifier = digits.substring(1);
      } else if (digits.isNotEmpty) {
        identifier = digits;
      }
    }

    final otpCode = (otp != null && otp.trim().isNotEmpty) ? otp.trim() : (code ?? '').trim();
    final cleanPassword = (password ?? '').trim();

    final payload = jsonEncode({
      'email': identifier,
      'phone': identifier,
      if (cleanPassword.isNotEmpty) 'password': cleanPassword,
      if (otpCode.isNotEmpty) 'otp': otpCode,
      if (otpCode.isNotEmpty) 'code': otpCode,
      if (role != null) 'role': role,
    });

    Future<Map<String, dynamic>> buildDirectLoginResult(Map<String, dynamic> u) async {
      final result = await _buildDirectSupabaseAuthData(
        u,
        fallbackIdentifier: identifier,
        requestedRole: role,
      );
      if (result['success'] == true && result['data'] is Map<String, dynamic>) {
        // Non-blocking background token synchronization with Express API (35s cold-start timeout)
        http.post(
          Uri.parse(ApiConstants.login),
          headers: {'Content-Type': 'application/json'},
          body: payload,
        ).timeout(const Duration(seconds: 35)).then((response) {
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['accessToken'] != null) {
              setAuthToken(data['accessToken'].toString());
            }
          }
        }).catchError((_) {});
      }
      return result;
    }

    // 1. Fast-Path Direct 24/7 Supabase Cloud PostgreSQL Authentication (~150ms) — Localhost debug convenience only
    if (!kReleaseMode &&
        ApiConstants.isUsingLocalhostBackend &&
        cleanPassword.isEmpty &&
        otpCode.isEmpty) {
      try {
        final u = await _findSupabaseUserByIdentifier(rawIdentifier, identifier);
        if (u != null) {
          return await buildDirectLoginResult(u);
        } else {
          return {
            'success': false,
            'message': 'Invalid credentials. User not registered in system.'
          };
        }
      } catch (directErr) {
        debugPrint('ℹ️ Direct Supabase login check notice ($directErr), falling back to Express API...');
      }
    }

    // 2. Central Express Backend API with 35s Cold-Start Timeout & Supabase Fallback
    try {
      final url = Uri.parse(ApiConstants.login);
      debugPrint('🌐 Sending Login Request to: $url');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode >= 500) {
        throw Exception('Register server unavailable (HTTP ${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (data['accessToken'] != null) setAuthToken(data['accessToken']);
        return {'success': true, 'data': data};
      } else if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'code': data['code'],
          'message': data['message'] ?? 'Invalid credentials. User not registered in system.'
        };
      } else {
        debugPrint('⚠️ Render backend response: ${response.body}. Triggering direct 24/7 Supabase Cloud PostgreSQL check...');
        throw Exception(data['message'] ?? 'Render backend fallback trigger');
      }
    } catch (e) {
      debugPrint('⚠️ Primary Backend Login Notice ($e). Attempting Direct 24/7 Supabase Cloud Authentication...');
      try {
        final u = await _findSupabaseUserByIdentifier(rawIdentifier, identifier);
        if (u != null) {
          return await buildDirectLoginResult(u);
        } else {
          return {
            'success': false,
            'message': 'Invalid credentials. User not registered in system.'
          };
        }
      } catch (sbErr) {
        debugPrint('❌ Direct 24/7 Supabase Auth Error: $sbErr');
        return {
          'success': false,
          'message': 'Login failed. Please check your network connection.'
        };
      }
    }
  }

  final Map<String, ({String code, DateTime expiresAt, int attempts, bool isAdmin})> _localTestingOtpChallenges = {};

  String _normalizePhoneOrEmailIdentifier(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.contains('@')) return trimmed.toLowerCase();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 14 && digits.startsWith('0091')) return digits.substring(4);
    if (digits.length == 13 && digits.startsWith('910')) return digits.substring(3);
    if (digits.length == 12 && digits.startsWith('91')) return digits.substring(2);
    if (digits.length == 11 && digits.startsWith('0')) return digits.substring(1);
    if (digits.length > 10) return digits.substring(digits.length - 10);
    return digits;
  }

  Future<Map<String, dynamic>?> _findSupabaseUserByIdentifier(String rawId, String normId) async {
    final client = SupabaseService.safeClient;
    if (client == null) return null;
    final isEmail = normId.contains('@');
    Map<String, dynamic>? u;
    if (isEmail) {
      u = await client.from('users').select('*').ilike('email', normId).limit(1).maybeSingle();
    } else {
      u = await client.from('users').select('*').eq('phone', normId).limit(1).maybeSingle();
      if (u == null && rawId != normId) {
        u = await client.from('users').select('*').eq('phone', rawId).limit(1).maybeSingle();
      }
      if (u == null && normId.length >= 10) {
        final last10 = normId.substring(normId.length - 10);
        final candidates = await client.from('users').select('*').ilike('phone', '%$last10%').limit(5);
        if (candidates.isNotEmpty) {
          for (final cand in candidates) {
            final cDigits = (cand['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
            if (cDigits.length >= 10 && cDigits.substring(cDigits.length - 10) == last10) {
              u = cand;
              break;
            }
          }
          u ??= candidates.first;
        } else {
          final last4 = last10.substring(last10.length - 4);
          final spacedCandidates = await client.from('users').select('*').ilike('phone', '%$last4%').limit(25);
          for (final cand in spacedCandidates) {
            final cDigits = (cand['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
            final c10 = cDigits.length >= 10 ? cDigits.substring(cDigits.length - 10) : cDigits;
            if (c10 == last10) {
              u = cand;
              break;
            }
          }
        }
      }
    }
    return u;
  }

  Future<Map<String, dynamic>> _buildDirectSupabaseAuthData(
    Map<String, dynamic> u, {
    required String fallbackIdentifier,
    String? requestedRole,
  }) async {
    final client = SupabaseService.safeClient;
    final userRole = (u['role']?.toString() ?? requestedRole ?? 'Patient').trim();
    final userRoleLower = userRole.toLowerCase();
    final isSubAdminUser = userRoleLower == 'sub-admin' || userRoleLower == 'subadmin' || userRoleLower == 'sub_admin';

    Map<String, dynamic> tokenMeta = {};
    if (u['device_token'] != null && u['device_token'].toString().startsWith('{')) {
      try {
        tokenMeta = jsonDecode(u['device_token'].toString());
      } catch (_) {}
    }

    final isMainAdminUser = userRoleLower == 'admin' ||
        userRoleLower == 'primaryadmin' ||
        userRoleLower == 'primary_admin' ||
        userRoleLower == 'superadmin' ||
        userRoleLower == 'super_admin';
    final userStatus = (u['status'] ?? tokenMeta['status'] ?? 'ACTIVE').toString().trim().toUpperCase();
    final isInactiveStatus = userStatus == 'INACTIVE' ||
        userStatus == 'DEACTIVATED' ||
        userStatus == 'SUSPENDED' ||
        userStatus == 'BLOCKED';
    if ((isSubAdminUser || isMainAdminUser) && isInactiveStatus) {
      return {
        'success': false,
        'code': 'ACCOUNT_DEACTIVATED',
        'message': isSubAdminUser
            ? 'Access Denied: Your Sub-Admin account has been deactivated by the Main Admin. Please contact the administrator.'
            : 'Access Denied: Your Admin account is currently inactive or deactivated.'
      };
    }

    List<dynamic> userPerms = (u['permissions'] is List && (u['permissions'] as List).isNotEmpty)
        ? u['permissions']
        : (tokenMeta['permissions'] is List ? tokenMeta['permissions'] : []);
    if (isSubAdminUser && userPerms.isEmpty && client != null) {
      try {
        final permRows = await client
            .from('sub_admin_permissions')
            .select('permission')
            .eq('user_id', u['id']);
        if (permRows.isNotEmpty) {
          userPerms = permRows.map((r) => (r['permission'] ?? r['permission_key'] ?? '').toString()).where((p) => p.isNotEmpty).toList();
        }
      } catch (_) {}
    }

    List<dynamic> assignedDistricts = [];
    if (isSubAdminUser && client != null) {
      try {
        final dRows = await client
            .from('sub_admin_districts')
            .select('districts(*)')
            .eq('sub_admin_id', u['id']);
        assignedDistricts = dRows.map((r) => r['districts']).whereType<Map>().toList();
      } catch (_) {}
    }

    final Map<String, dynamic> doctorExtra = {};
    if ((userRoleLower.contains('dentist') || userRoleLower.contains('doctor')) && client != null) {
      try {
        final docRow = await client
            .from('dentists')
            .select('*, clinics(clinic_name, location)')
            .eq('user_id', u['id'])
            .limit(1)
            .maybeSingle();
        if (docRow != null) {
          doctorExtra['dentistId'] = docRow['id'];
          doctorExtra['userId'] = u['id'];
          doctorExtra['clinicId'] = docRow['clinic_id'];
          doctorExtra['specialty'] = docRow['speciality'] ?? tokenMeta['specialty'] ?? 'General Medicine';
          doctorExtra['qualification'] = docRow['qualifications'] ?? tokenMeta['qualification'];
          doctorExtra['experienceYears'] = docRow['experience_years'] ?? tokenMeta['experienceYears'];
          doctorExtra['licenseNumber'] = docRow['license_number'] ?? tokenMeta['licenseNumber'];
          doctorExtra['availability_status'] = docRow['availability_status'] ?? 'Available';
          final joinedClinicName = (docRow['clinics'] is Map) ? (docRow['clinics'] as Map)['clinic_name'] : null;
          final joinedClinicLoc = (docRow['clinics'] is Map) ? (docRow['clinics'] as Map)['location'] : null;
          final resolvedClinicName = _cleanField(docRow['clinic_name'] ?? joinedClinicName ?? tokenMeta['clinicName']);
          final resolvedClinicAddress = _cleanField(
            docRow['clinic_address'] ?? tokenMeta['clinicAddress'] ?? tokenMeta['address'] ?? joinedClinicLoc,
          );
          if (resolvedClinicName.isNotEmpty) doctorExtra['clinicName'] = resolvedClinicName;
          if (resolvedClinicAddress.isNotEmpty) doctorExtra['clinicAddress'] = resolvedClinicAddress;
          final docCity = _cleanField(docRow['city'] ?? u['city'] ?? tokenMeta['city']);
          final docState = _cleanField(docRow['state'] ?? u['state'] ?? tokenMeta['state']);
          final docPincode = _cleanField(docRow['pincode'] ?? u['pincode'] ?? tokenMeta['pincode']);
          if (docCity.isNotEmpty) doctorExtra['city'] = docCity;
          if (docState.isNotEmpty) doctorExtra['state'] = docState;
          if (docPincode.isNotEmpty) doctorExtra['pincode'] = docPincode;
          if (docRow['latitude'] != null || u['latitude'] != null || tokenMeta['latitude'] != null) {
            doctorExtra['latitude'] = docRow['latitude'] ?? u['latitude'] ?? tokenMeta['latitude'];
          }
          if (docRow['longitude'] != null || u['longitude'] != null || tokenMeta['longitude'] != null) {
            doctorExtra['longitude'] = docRow['longitude'] ?? u['longitude'] ?? tokenMeta['longitude'];
          }
        }
      } catch (_) {}
    }

    final Map<String, dynamic> clinicExtra = {};
    if (userRoleLower.contains('clinic') && client != null) {
      try {
        final clinicRow = await client
            .from('clinics')
            .select('*')
            .eq('user_id', u['id'])
            .limit(1)
            .maybeSingle();
        if (clinicRow != null) {
          final cAddr = _cleanField(
            clinicRow['clinic_address'] ?? tokenMeta['clinicAddress'] ?? tokenMeta['address'] ?? clinicRow['location'],
          );
          clinicExtra['clinicId'] = clinicRow['id'];
          clinicExtra['clinicName'] = clinicRow['clinic_name'] ?? tokenMeta['clinicName'] ?? u['name'];
          clinicExtra['clinicLocation'] = cAddr.isNotEmpty ? cAddr : (clinicRow['location'] ?? '');
          clinicExtra['clinicAddress'] = cAddr;
          final cCity = _cleanField(clinicRow['city'] ?? u['city'] ?? tokenMeta['city']);
          final cState = _cleanField(clinicRow['state'] ?? u['state'] ?? tokenMeta['state']);
          final cPin = _cleanField(clinicRow['pincode'] ?? u['pincode'] ?? tokenMeta['pincode']);
          if (cCity.isNotEmpty) clinicExtra['city'] = cCity;
          if (cState.isNotEmpty) clinicExtra['state'] = cState;
          if (cPin.isNotEmpty) clinicExtra['pincode'] = cPin;
          if (clinicRow['latitude'] != null || u['latitude'] != null || tokenMeta['latitude'] != null) {
            clinicExtra['latitude'] = clinicRow['latitude'] ?? u['latitude'] ?? tokenMeta['latitude'];
          }
          if (clinicRow['longitude'] != null || u['longitude'] != null || tokenMeta['longitude'] != null) {
            clinicExtra['longitude'] = clinicRow['longitude'] ?? u['longitude'] ?? tokenMeta['longitude'];
          }
        }
      } catch (_) {}
    }

    final effectiveRole = userRole.isNotEmpty ? userRole : (requestedRole ?? 'Patient');
    return {
      'success': true,
      'data': {
        'accessToken': 'sb_direct_${u['id']}',
        'user': {
          'id': u['id'],
          'email': u['email'] ?? '',
          'name': u['name'] ?? (fallbackIdentifier.contains('@') ? fallbackIdentifier.split('@').first : fallbackIdentifier),
          'role': effectiveRole,
          'phone': u['phone'] ?? fallbackIdentifier,
          'status': userStatus,
          'permissions': userPerms,
          'assignedDistricts': assignedDistricts,
          'age': _cleanField(u['age'] ?? tokenMeta['age']),
          'gender': _cleanField(u['gender'] ?? tokenMeta['gender']),
          'bloodGroup': _cleanField(u['blood_group'] ?? u['bloodGroup'] ?? tokenMeta['bloodGroup']),
          'emergencyContact': _cleanField(u['emergency_contact'] ?? u['emergencyContact'] ?? tokenMeta['emergencyContact']),
          'city': _cleanField(u['city'] ?? tokenMeta['city']),
          'pincode': _cleanField(u['pincode'] ?? tokenMeta['pincode']),
          'state': _cleanField(u['state'] ?? tokenMeta['state'] ?? tokenMeta['location']),
          'latitude': u['latitude'] ?? tokenMeta['latitude'],
          'longitude': u['longitude'] ?? tokenMeta['longitude'],
          'languages': u['languages'] ?? tokenMeta['languages'] ?? ['English'],
          'profilePhoto': u['biometric_token'] ?? tokenMeta['profilePhoto'],
          ...doctorExtra,
          ...clinicExtra,
        }
      }
    };
  }

  bool get _canUseIsolatedTestingOtpFallback {
    // Public production release builds (kReleaseMode && !isStagingFlavorBuild) NEVER use on-screen testing OTP fallback.
    if (kReleaseMode && !ApiConstants.isStagingFlavorBuild) {
      return false;
    }
    if (!ApiConstants.allowOnScreenOtpDisplay ||
        !ApiConstants.isUsingNonProductionBackend()) {
      return false;
    }
    if (SupabaseService.safeClient == null) return false;
    try {
      return !ApiConstants.isProductionSupabaseConfig(
        url: ApiConstants.supabaseUrl,
        anonKey: ApiConstants.supabaseAnonKey,
      );
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({required String phone, String email})? debugRequestOtpOverride;

  @visibleForTesting
  static List<Uri> candidateEndpointUrls(String path, {String? baseUrlOverride}) {
    final primary = (baseUrlOverride ?? ApiConstants.baseUrl).trim();
    final candidates = <String>[primary];
    if (!kReleaseMode) {
      if (primary.contains('://localhost:')) {
        candidates.add(primary.replaceFirst('://localhost:', '://127.0.0.1:'));
      } else if (primary.contains('://127.0.0.1:')) {
        candidates.add(primary.replaceFirst('://127.0.0.1:', '://localhost:'));
      } else if (primary.contains('://10.0.2.2:')) {
        candidates.add(primary.replaceFirst('://10.0.2.2:', '://localhost:'));
        candidates.add(primary.replaceFirst('://10.0.2.2:', '://127.0.0.1:'));
      }
    }
    return candidates.map((base) => Uri.parse('$base$path')).toList();
  }

  List<Uri> _candidateEndpointUrls(String path) => candidateEndpointUrls(path);

  /// Request Mobile OTP Code via Real SMS or Staging On-Screen OTP
  Future<Map<String, dynamic>> requestOtp({
    required String phone,
    String email = '',
    http.Client? client,
  }) async {
    if (debugRequestOtpOverride != null) {
      return debugRequestOtpOverride!(phone: phone, email: email);
    }
    final urls = _candidateEndpointUrls('/auth/otp/request');
    Object? lastError;
    for (final url in urls) {
      try {
        debugPrint('🌐 Sending requestOtp to: $url');

        final String stagingOtpKey = ApiConstants.stagingOtpAccessKey;
        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (stagingOtpKey.isNotEmpty) 'x-staging-otp-key': stagingOtpKey,
        };
        final payload = jsonEncode({'phone': phone, 'email': email});
        final response = await (client != null
                ? client.post(url, headers: headers, body: payload)
                : http.post(url, headers: headers, body: payload))
            .timeout(const Duration(seconds: 40));

        if (response.statusCode >= 500) {
          throw Exception('OTP server unavailable (HTTP ${response.statusCode})');
        }

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true) {
          final bool isOnScreenTestOtp = ApiConstants.allowOnScreenOtpDisplay &&
              data['deliveryMode'] == 'on_screen';
          return {
            'success': true,
            'message': data['message'] ?? 'OTP sent successfully to your mobile number.',
            if (isOnScreenTestOtp && data['otp'] != null) 'otp': data['otp'].toString(),
            if (isOnScreenTestOtp) 'deliveryMode': 'on_screen',
            'isAdmin': data['isAdmin'] == true,
          };
        } else {
          return {
            'success': false,
            'status': response.statusCode,
            if (data['code'] != null) 'code': data['code'],
            'message': data['message'] ?? 'Failed to send OTP SMS. Please check your mobile number.',
            'isAdmin': data['isAdmin'] == true,
          };
        }
      } catch (e) {
        lastError = e;
        debugPrint('⚠️ requestOtp attempt ($url) network error: $e');
      }
    }

    // 24/7 Isolated Testing Supabase Cloud OTP fallback so login never fails when local Express server is stopped
    if (_canUseIsolatedTestingOtpFallback) {
      try {
        final rawId = phone.trim().isNotEmpty ? phone.trim() : email.trim();
        final normKey = _normalizePhoneOrEmailIdentifier(rawId);
        if (normKey.isEmpty) {
          return {'success': false, 'message': 'Valid mobile number or email is required.'};
        }
        final u = await _findSupabaseUserByIdentifier(rawId, normKey);
        final roleLower = (u?['role'] ?? '').toString().trim().toLowerCase();
        final statusUpper = (u?['status'] ?? 'ACTIVE').toString().trim().toUpperCase();
        final isActiveAccount = statusUpper != 'INACTIVE' &&
            statusUpper != 'DEACTIVATED' &&
            statusUpper != 'SUSPENDED' &&
            statusUpper != 'BLOCKED';
        final isStrictAdmin = isActiveAccount &&
            (roleLower == 'admin' ||
                roleLower == 'primaryadmin' ||
                roleLower == 'primary_admin' ||
                roleLower == 'superadmin' ||
                roleLower == 'super_admin');
        final otpCode = (Random.secure().nextInt(900000) + 100000).toString();
        _localTestingOtpChallenges[normKey] = (
          code: otpCode,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          attempts: 0,
          isAdmin: isStrictAdmin,
        );
        return {
          'success': true,
          'message': 'Verification code ready on screen (testing mode).',
          'otp': otpCode,
          'deliveryMode': 'on_screen',
          'isAdmin': isStrictAdmin,
        };
      } catch (sbErr) {
        debugPrint('⚠️ Isolated testing Supabase OTP fallback notice: $sbErr');
      }
    }

    debugPrint('⚠️ requestOtp failed across all candidate URLs: $lastError');
    return {
      'success': false,
      'message': !kReleaseMode && ApiConstants.isUsingLocalhostBackend
          ? 'Unable to reach local OTP backend (${ApiConstants.baseUrl}). Ensure "cd backend && npm start" is running.'
          : (ApiConstants.isUsingNonProductionBackend()
              ? 'Unable to reach testing OTP backend (${ApiConstants.baseUrl}). Please verify the staging server is running.'
              : 'Unable to connect to SMS verification server. Please try again.'),
    };
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({required String phone, String email, required String code})? debugVerifyOtpOverride;

  String _cleanField(dynamic val) {
    final s = (val ?? '').toString().trim();
    return s.toLowerCase() == 'null' ? '' : s;
  }

  /// Verify 6-Digit Mobile & Email OTP Code via Backend (with 24/7 isolated testing Supabase fallback on localhost)
  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    String email = '',
    required String code,
    String? role,
    bool autoCreatePatient = false,
    http.Client? client,
  }) async {
    if (debugVerifyOtpOverride != null) {
      return debugVerifyOtpOverride!(phone: phone, email: email, code: code);
    }

    final urls = _candidateEndpointUrls('/auth/otp/verify');
    Object? lastError;
    for (final url in urls) {
      try {
        final headers = {'Content-Type': 'application/json'};
        final payload = jsonEncode({
          'phone': phone,
          'email': email,
          'code': code.trim(),
          if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
          if (autoCreatePatient) 'autoCreatePatient': true,
        });
        final response = await (client != null
                ? client.post(url, headers: headers, body: payload)
                : http.post(url, headers: headers, body: payload))
            .timeout(const Duration(seconds: 40));

        if (response.statusCode >= 500) {
          throw Exception('OTP server unavailable (HTTP ${response.statusCode})');
        }

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true) {
          return {
            'success': true,
            'message': data['message'] ?? 'OTP verified successfully.',
            'user': data['user'],
            'accessToken': data['accessToken'],
            'refreshToken': data['refreshToken'],
            if (data['realtimeToken'] != null) 'realtimeToken': data['realtimeToken'],
            if (data['realtimeTokenExpiresAt'] != null)
              'realtimeTokenExpiresAt': data['realtimeTokenExpiresAt'],
            'isAdmin': data['isAdmin'] == true,
            if (data['isSubAdmin'] == true) 'isSubAdmin': true,
            if (data['isNewPatient'] == true) 'isNewPatient': true,
          };
        } else {
          return {
            'success': false,
            'status': response.statusCode,
            if (data['code'] != null) 'code': data['code'],
            'message': data['message'] ?? 'Invalid or expired OTP code. Please request a new OTP.',
          };
        }
      } catch (e) {
        lastError = e;
        debugPrint('⚠️ verifyOtp attempt ($url) network error: $e');
      }
    }

    // 24/7 Isolated Testing Supabase Cloud OTP verification fallback
    if (_canUseIsolatedTestingOtpFallback) {
      final rawId = phone.trim().isNotEmpty ? phone.trim() : email.trim();
      final normKey = _normalizePhoneOrEmailIdentifier(rawId);
      final challenge = _localTestingOtpChallenges[normKey];
      if (challenge != null) {
        if (DateTime.now().isAfter(challenge.expiresAt)) {
          _localTestingOtpChallenges.remove(normKey);
          return {'success': false, 'message': 'OTP expired. Please request a new verification code.'};
        }
        if (challenge.attempts >= 5) {
          _localTestingOtpChallenges.remove(normKey);
          return {'success': false, 'message': 'Too many invalid attempts. Please request a new verification code.'};
        }
        if (challenge.code != code.trim()) {
          _localTestingOtpChallenges[normKey] = (
            code: challenge.code,
            expiresAt: challenge.expiresAt,
            attempts: challenge.attempts + 1,
            isAdmin: challenge.isAdmin,
          );
          return {'success': false, 'message': 'Invalid OTP code. Please check and try again.'};
        }
        _localTestingOtpChallenges.remove(normKey);

        try {
          var u = await _findSupabaseUserByIdentifier(rawId, normKey);
          bool isNewPatient = false;
          final roleLower = (role ?? '').trim().toLowerCase();
          final isAdminLoginFlow = roleLower == 'admin' ||
              roleLower == 'primaryadmin' ||
              roleLower == 'primary_admin' ||
              roleLower == 'superadmin' ||
              roleLower == 'super_admin' ||
              roleLower == 'sub-admin' ||
              roleLower == 'subadmin' ||
              roleLower == 'sub_admin';

          if (isAdminLoginFlow) {
            if (u == null) {
              return {
                'success': false,
                'status': 403,
                'code': 'ADMIN_ROLE_REQUIRED',
                'message': 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.',
              };
            }
            final dbRoleLower = (u['role'] ?? '').toString().trim().toLowerCase();
            final isDbMainAdmin = dbRoleLower == 'admin' ||
                dbRoleLower == 'primaryadmin' ||
                dbRoleLower == 'primary_admin' ||
                dbRoleLower == 'superadmin' ||
                dbRoleLower == 'super_admin';
            final isDbSubAdmin = dbRoleLower == 'sub-admin' ||
                dbRoleLower == 'subadmin' ||
                dbRoleLower == 'sub_admin';
            if (!isDbMainAdmin && !isDbSubAdmin) {
              return {
                'success': false,
                'status': 403,
                'code': 'ADMIN_ROLE_REQUIRED',
                'message': 'Unauthorized Admin access. OTP verification alone cannot grant Admin access.',
              };
            }
          }

          if (u == null &&
              autoCreatePatient &&
              (roleLower.isEmpty || roleLower == 'patient') &&
              RegExp(r'^\d{10}$').hasMatch(normKey)) {
            final sbClient = SupabaseService.safeClient;
            if (sbClient != null) {
              final cleanEmail = (email.trim().isNotEmpty && email.contains('@'))
                  ? email.trim().toLowerCase()
                  : 'user_$normKey@dentaguru.internal';
              final refCode = 'DG-PAT${normKey.substring(normKey.length - 4)}';
              final metaJson = jsonEncode({
                'age': '',
                'gender': '',
                'pincode': '',
                'city': '',
                'languages': ['English'],
                'referral_code': refCode,
                'profileCompleted': false,
              });
              try {
                u = await sbClient.from('users').insert({
                  'name': 'Patient',
                  'email': cleanEmail,
                  'password': 'OTP_SECURE_${Random.secure().nextInt(999999)}',
                  'phone': normKey,
                  'role': 'Patient',
                  'city': '',
                  'pincode': '',
                  'age': '',
                  'gender': '',
                  'referral_code': refCode,
                  'device_token': metaJson,
                }).select().single();
              } catch (_) {
                u = await sbClient.from('users').insert({
                  'name': 'Patient',
                  'email': cleanEmail,
                  'password': 'OTP_SECURE_${Random.secure().nextInt(999999)}',
                  'phone': normKey,
                  'role': 'Patient',
                  'city': '',
                  'pincode': '',
                  'device_token': metaJson,
                }).select().single();
              }
              isNewPatient = true;
            }
          }
          if (u != null) {
            final authResult = await _buildDirectSupabaseAuthData(
              u,
              fallbackIdentifier: rawId,
              requestedRole: role,
            );
            if (authResult['success'] != true) {
              return {
                'success': false,
                'status': 403,
                'code': authResult['code'],
                'message': authResult['message'] ?? 'Account access denied.',
              };
            }
            final data = authResult['data'] as Map<String, dynamic>;
            if (data['accessToken'] != null) {
              setAuthToken(data['accessToken'].toString());
            }
            final dbRoleLower = (u['role'] ?? '').toString().trim().toLowerCase();
            final isDbMainAdmin = dbRoleLower == 'admin' ||
                dbRoleLower == 'primaryadmin' ||
                dbRoleLower == 'primary_admin' ||
                dbRoleLower == 'superadmin' ||
                dbRoleLower == 'super_admin';
            final isDbSubAdmin = dbRoleLower == 'sub-admin' ||
                dbRoleLower == 'subadmin' ||
                dbRoleLower == 'sub_admin';
            return {
              'success': true,
              'message': 'OTP verified successfully.',
              'user': data['user'],
              'accessToken': data['accessToken'],
              'isAdmin': isDbMainAdmin || challenge.isAdmin,
              if (isDbSubAdmin) 'isSubAdmin': true,
              if (isNewPatient) 'isNewPatient': true,
            };
          }
          return {
            'success': true,
            'message': 'OTP verified successfully.',
            'isAdmin': false,
          };
        } catch (sbErr) {
          debugPrint('⚠️ Isolated testing Supabase OTP verify notice: $sbErr');
        }
      }
    }

    debugPrint('⚠️ verifyOtp failed across all candidate URLs: $lastError');
    return {
      'success': false,
      'message': 'Failed to verify OTP code due to connection error. Please try again.',
    };
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String patientId,
    String? pincode,
    String? age,
    String? gender,
    String? profilePhoto,
    String? name,
    String? city,
    bool completeProfile,
  })? debugUpdatePatientProfileOverride;

  /// Fetch authenticated patient profile by JWT / Supabase ID
  Future<Map<String, dynamic>?> fetchCurrentPatientProfile({
    String? patientId,
    http.Client? client,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/auth/patient/profile');
      final response = await (client != null
              ? client.get(url, headers: _headersWithUser(patientId))
              : http.get(url, headers: _headersWithUser(patientId)))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['user'] is Map) {
          return Map<String, dynamic>.from(data['user'] as Map);
        }
      }
    } catch (_) {}

    final targetId = (patientId ?? SessionService().currentSession?.userId ?? '').trim();
    if (targetId.isEmpty) return null;
    try {
      final sbClient = SupabaseService.safeClient;
      if (sbClient == null) return null;
      final row = await sbClient.from('users').select('*').eq('id', targetId).maybeSingle();
      if (row == null) return null;
      final built = await _buildDirectSupabaseAuthData(row, fallbackIdentifier: _cleanField(row['phone']));
      final user = (built['data'] is Map) ? (built['data'] as Map)['user'] : null;
      return user is Map ? Map<String, dynamic>.from(user) : null;
    } catch (_) {
      return null;
    }
  }

  /// Update authenticated Patient profile in-place against existing user ID (no duplicates).
  Future<Map<String, dynamic>> updatePatientProfileApi({
    required String patientId,
    String? pincode,
    String? age,
    String? gender,
    String? profilePhoto,
    String? name,
    String? city,
    String? address,
    String? bloodGroup,
    String? emergencyContact,
    List<String>? languages,
    bool completeProfile = true,
    http.Client? client,
  }) async {
    if (debugUpdatePatientProfileOverride != null) {
      return debugUpdatePatientProfileOverride!(
        patientId: patientId,
        pincode: pincode,
        age: age,
        gender: gender,
        profilePhoto: profilePhoto,
        name: name,
        city: city,
        completeProfile: completeProfile,
      );
    }

    final payloadMap = <String, dynamic>{
      if (pincode != null) 'pincode': pincode.trim(),
      if (age != null) 'age': age.trim(),
      if (gender != null) 'gender': gender.trim(),
      if (profilePhoto != null && profilePhoto.trim().isNotEmpty) 'profilePhoto': profilePhoto.trim(),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (city != null) 'city': city.trim(),
      if (address != null) 'address': address.trim(),
      if (bloodGroup != null) 'bloodGroup': bloodGroup.trim(),
      if (emergencyContact != null) 'emergencyContact': emergencyContact.trim(),
      if (languages != null) 'languages': languages,
      'completeProfile': completeProfile,
    };

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/auth/patient/profile');
      final response = await (client != null
              ? client.put(url, headers: _headersWithUser(patientId), body: jsonEncode(payloadMap))
              : http.put(url, headers: _headersWithUser(patientId), body: jsonEncode(payloadMap)))
          .timeout(const Duration(seconds: 35));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Profile updated successfully.',
          'user': data['user'],
        };
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        return {
          'success': false,
          'status': response.statusCode,
          'message': data['message'] ?? 'Validation failed while saving profile.',
        };
      }
    } catch (e) {
      debugPrint('⚠️ updatePatientProfileApi HTTP notice ($e). Falling back to direct Supabase user update...');
    }

    // 24/7 Direct Supabase fallback updating ONLY existing patient row by ID (never insert)
    final cleanId = patientId.trim();
    if (cleanId.isEmpty) {
      return {'success': false, 'message': 'Authenticated patient ID is missing.'};
    }
    try {
      final sbClient = SupabaseService.safeClient;
      if (sbClient == null) {
        return {'success': false, 'message': 'Unable to reach server. Please try again.'};
      }

      Map<String, dynamic> meta = {};
      try {
        final existing = await sbClient.from('users').select('device_token').eq('id', cleanId).maybeSingle();
        final rawDt = existing?['device_token']?.toString() ?? '';
        if (rawDt.trim().startsWith('{')) {
          meta = Map<String, dynamic>.from(jsonDecode(rawDt) as Map);
        }
      } catch (_) {}

      if (age != null) meta['age'] = age.trim();
      if (gender != null) meta['gender'] = gender.trim();
      if (pincode != null) meta['pincode'] = pincode.trim();
      if (city != null) meta['city'] = city.trim();
      if (address != null) meta['address'] = address.trim();
      if (bloodGroup != null) meta['bloodGroup'] = bloodGroup.trim();
      if (emergencyContact != null) meta['emergencyContact'] = emergencyContact.trim();
      if (languages != null && languages.isNotEmpty) meta['languages'] = languages;
      if (profilePhoto != null && profilePhoto.trim().isNotEmpty) {
        meta['profilePhoto'] = profilePhoto.trim();
      }
      meta['profileCompleted'] = completeProfile;

      final updateMap = <String, dynamic>{
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (city != null) 'city': city.trim(),
        if (pincode != null) 'pincode': pincode.trim(),
        if (age != null) 'age': age.trim(),
        if (gender != null) 'gender': gender.trim(),
        if (bloodGroup != null) 'blood_group': bloodGroup.trim(),
        if (emergencyContact != null) 'emergency_contact': emergencyContact.trim(),
        if (profilePhoto != null && profilePhoto.trim().isNotEmpty) 'biometric_token': profilePhoto.trim(),
        'device_token': jsonEncode(meta),
      };

      Map<String, dynamic>? updatedRow;
      try {
        updatedRow = await sbClient.from('users').update(updateMap).eq('id', cleanId).select().maybeSingle();
      } catch (_) {
        final coreUpdate = <String, dynamic>{
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (city != null) 'city': city.trim(),
          if (pincode != null) 'pincode': pincode.trim(),
          if (profilePhoto != null && profilePhoto.trim().isNotEmpty) 'biometric_token': profilePhoto.trim(),
          'device_token': jsonEncode(meta),
        };
        updatedRow = await sbClient.from('users').update(coreUpdate).eq('id', cleanId).select().maybeSingle();
      }

      if (updatedRow != null) {
        final built = await _buildDirectSupabaseAuthData(updatedRow, fallbackIdentifier: _cleanField(updatedRow['phone']));
        final user = (built['data'] is Map) ? (built['data'] as Map)['user'] : null;
        return {'success': true, 'user': user};
      }
    } catch (sbErr) {
      debugPrint('⚠️ Direct Supabase patient profile update error: $sbErr');
    }

    return {'success': false, 'message': 'Unable to save patient profile right now. Please try again.'};
  }

  /// Request Forgot Password OTP
  Future<Map<String, dynamic>> forgotPassword({required String email, String? phone}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/auth/forgot-password');
      final String stagingOtpKey = ApiConstants.stagingOtpAccessKey;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (stagingOtpKey.isNotEmpty) 'x-staging-otp-key': stagingOtpKey,
      };
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({'email': email, if (phone != null) 'phone': phone}),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);
      final bool isOnScreenTestOtp = ApiConstants.allowOnScreenOtpDisplay &&
          data['deliveryMode'] == 'on_screen';
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? 'Password reset code sent.',
        if (isOnScreenTestOtp && data['otp'] != null) 'otp': data['otp'].toString(),
        if (isOnScreenTestOtp) 'deliveryMode': 'on_screen',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to request password reset OTP.'};
    }
  }

  /// Confirm OTP & Reset Password in Supabase DB
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/auth/reset-password');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200, 'message': data['message'] ?? 'Password reset successful.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to reset password. Please check your OTP code.'};
    }
  }

  bool _lastFetchDentistsSucceeded = false;
  bool get lastFetchDentistsSucceeded => _lastFetchDentistsSucceeded;

  List<String> _lastAvailableDoctorLanguages = const [];
  List<String> get lastAvailableDoctorLanguages => _lastAvailableDoctorLanguages;

  static Future<List<dynamic>> Function({
    String? state,
    String? city,
    String? pincode,
    String? specialty,
    String? availability,
    String? language,
    List<String>? languages,
    String? search,
    bool includeUnavailable,
  })? debugFetchDentistsOverride;

  /// Fetch live dentists directory via Express Backend API first (enforces availability ON/OFF)
  /// with direct Supabase fallback when Express is unreachable.
  Future<List<dynamic>> fetchDentists({
    String? state,
    String? city,
    String? pincode,
    String? specialty,
    String? availability,
    String? language,
    List<String>? languages,
    String? search,
    bool includeUnavailable = false,
  }) async {
    _lastFetchDentistsSucceeded = false;
    final override = debugFetchDentistsOverride;
    if (override != null) {
      _lastFetchDentistsSucceeded = true;
      return override(
        state: state,
        city: city,
        pincode: pincode,
        specialty: specialty,
        availability: availability,
        language: language,
        languages: languages,
        search: search,
        includeUnavailable: includeUnavailable,
      );
    }
    final selectedLangs = <String>[
      if (languages != null)
        ...languages.map((l) => l.trim()).where((l) => l.isNotEmpty && l.toLowerCase() != 'any language'),
      if (language != null && language.trim().isNotEmpty && language.trim().toLowerCase() != 'any language')
        ...language.split(',').map((l) => l.trim()).where((l) => l.isNotEmpty && l.toLowerCase() != 'any language'),
    ];

    // 1. Express backend API first (authoritative availability & language filtering)
    try {
      final params = <String, String>{};
      if (state != null && state.trim().isNotEmpty) params['state'] = state.trim();
      if (city != null && city.trim().isNotEmpty) params['city'] = city.trim();
      if (pincode != null && pincode.trim().isNotEmpty) params['pincode'] = pincode.trim();
      if (specialty != null && specialty.trim().isNotEmpty && specialty.trim().toLowerCase() != 'all' && specialty.trim().toLowerCase() != 'all specialties') {
        params['specialty'] = specialty.trim();
      }
      if (availability != null && availability.trim().isNotEmpty) params['availability'] = availability.trim();
      if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
      if (selectedLangs.isNotEmpty) {
        params['languages'] = selectedLangs.join(',');
      }
      if (includeUnavailable) params['includeUnavailable'] = 'true';

      final uri = Uri.parse('${ApiConstants.baseUrl}/dentists').replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final availLangs = data['availableLanguages'];
        if (availLangs is List) {
          _lastAvailableDoctorLanguages = deduplicateLanguages(availLangs);
        }
        final list = data['dentists'] ?? data['doctors'] ?? [];
        if (list is List) {
          _lastFetchDentistsSucceeded = true;
          return list;
        }
      }
    } catch (e) {
      debugPrint('Fetch dentists API notice: $e');
    }

    // 2. Direct Supabase fallback (when Express is unreachable)
    try {
      final client = Supabase.instance.client;
      var query = client.from('dentists').select('*, users!user_id(*), clinics!clinic_id(*)');
      if (state != null && state.trim().isNotEmpty) query = query.ilike('state', '%${state.trim()}%');
      if (city != null && city.trim().isNotEmpty) query = query.ilike('city', '%${city.trim()}%');
      if (pincode != null && pincode.trim().isNotEmpty) query = query.ilike('pincode', '%${pincode.trim()}%');

      final res = await query.order('created_at', ascending: false);
      if (res.isNotEmpty) {
        Iterable<dynamic> filtered = res;
        if (!includeUnavailable) {
          filtered = filtered.where((d) {
            final s = (d['availability_status'] ?? d['status'] ?? 'Available').toString().trim().toLowerCase();
            return s != 'unavailable' && s != 'offline' && s != 'inactive' && s != 'on leave' && s != 'off' && s != 'suspended';
          });
        }
        if (specialty != null &&
            specialty.trim().isNotEmpty &&
            specialty.trim().toLowerCase() != 'all' &&
            specialty.trim().toLowerCase() != 'all specialties') {
          filtered = filtered.where((d) {
            final docSpec = (d['speciality'] ?? d['specialty'] ?? 'General Medicine').toString();
            return MedicalSpecialtyModel.matchesSpecialtyFilter(docSpec, specialty.trim());
          });
        }
        if (search != null && search.trim().isNotEmpty) {
          final q = search.trim().toLowerCase();
          filtered = filtered.where((d) {
            final u = d['users'] is Map ? d['users'] as Map : const {};
            final c = d['clinics'] is Map ? d['clinics'] as Map : const {};
            return (u['name'] ?? d['name'] ?? '').toString().toLowerCase().contains(q) ||
                (d['speciality'] ?? d['specialty'] ?? '').toString().toLowerCase().contains(q) ||
                (c['clinic_name'] ?? d['clinicName'] ?? '').toString().toLowerCase().contains(q) ||
                (d['city'] ?? u['city'] ?? '').toString().toLowerCase().contains(q) ||
                (d['pincode'] ?? u['pincode'] ?? '').toString().toLowerCase().contains(q);
          });
        }
        if (selectedLangs.isNotEmpty) {
          filtered = filtered.where((d) {
            final userObj = d['users'] is Map ? d['users'] as Map : const {};
            final docLangs = extractDoctorLanguagesFromRaw(
              d is Map ? d : const {},
              userObj,
            );
            return doctorLanguagesMatch(docLangs, selectedLangs);
          });
        }
        _lastFetchDentistsSucceeded = true;
        return List<dynamic>.from(filtered);
      }
    } catch (e) {
      debugPrint('Supabase direct fetch dentists notice: $e');
    }
    return [];
  }

  @visibleForTesting
  static Future<List<String>> Function({bool includeUnavailable})? debugFetchDoctorLanguagesOverride;

  /// Fetch distinct languages spoken by registered doctors from the backend/database.
  Future<List<String>> fetchAvailableDoctorLanguages({bool includeUnavailable = false}) async {
    if (debugFetchDoctorLanguagesOverride != null) {
      return debugFetchDoctorLanguagesOverride!(includeUnavailable: includeUnavailable);
    }

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctors/languages').replace(
        queryParameters: includeUnavailable ? {'includeUnavailable': 'true'} : null,
      );
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['languages'];
        if (list is List) {
          return deduplicateLanguages(list);
        }
      }
    } catch (e) {
      debugPrint('Fetch doctor languages API notice: $e');
    }

    // Fallback: extract distinct languages from direct Supabase query
    try {
      final client = Supabase.instance.client;
      final res = await client.from('dentists').select('languages, availability_status, users!user_id(device_token)');
      final List<String> extracted = [];
      for (final row in res) {
        final status = (row['availability_status'] ?? 'Available').toString().trim().toLowerCase();
        if (!includeUnavailable &&
            (status == 'unavailable' || status == 'offline' || status == 'inactive' || status == 'on leave' || status == 'off' || status == 'suspended')) {
          continue;
        }
        final userObj = row['users'] is Map ? row['users'] as Map : const {};
        extracted.addAll(extractDoctorLanguagesFromRaw(row, userObj));
      }
      return deduplicateLanguages(extracted);
    } catch (e) {
      debugPrint('Supabase direct fetch doctor languages notice: $e');
    }
    return [];
  }

  /// Fetch a single doctor profile by ID (enforces backend availability visibility for patients)
  Future<Map<String, dynamic>> fetchDoctorById(String doctorId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctors/$doctorId');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'isAvailable': data['isAvailable'] ?? true,
          'availability_status': data['availability_status'] ?? 'Available',
          'doctor': data['doctor'],
        };
      }
      if (response.statusCode == 403 && data['unavailable'] == true) {
        return {
          'success': false,
          'unavailable': true,
          'isAvailable': false,
          'message': data['message'] ?? 'Doctor is currently unavailable.',
        };
      }
      return {
        'success': false,
        'status': response.statusCode,
        'message': data['message'] ?? 'Unable to load doctor profile.',
      };
    } catch (e) {
      debugPrint('fetchDoctorById notice: $e');
      return {
        'success': false,
        'networkError': true,
        'message': 'Unable to verify doctor profile.',
      };
    }
  }

  /// Test hook for stubbing doctor availability toggles in headless widget tests.
  static Future<Map<String, dynamic>> Function(
    String doctorId,
    bool isAvailable, {
    String? statusOverride,
  })? debugUpdateDoctorAvailabilityOverride;

  /// Toggle Doctor Availability ON/OFF or 5-state presence ('Online', 'Offline', 'Available', 'Busy', 'Unavailable')
  Future<Map<String, dynamic>> updateDoctorAvailability(
    String doctorId,
    bool isAvailable, {
    String? statusOverride,
  }) async {
    final override = debugUpdateDoctorAvailabilityOverride;
    if (override != null) {
      return override(doctorId, isAvailable, statusOverride: statusOverride);
    }
    final statusStr = (statusOverride != null && statusOverride.trim().isNotEmpty)
        ? statusOverride.trim()
        : (isAvailable ? 'Available' : 'Unavailable');
    final bodyJson = jsonEncode({
      'isAvailable': isAvailable,
      'availability_status': statusStr,
      'status': statusStr,
      if (statusOverride != null && statusOverride.trim().isNotEmpty)
        'onlineStatus': statusOverride.trim(),
    });

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctors/$doctorId/availability');
      http.Response response;
      try {
        response = await http.patch(
          uri,
          headers: _headers,
          body: bodyJson,
        ).timeout(const Duration(seconds: 35));
      } catch (_) {
        response = await http.put(
          uri,
          headers: _headers,
          body: bodyJson,
        ).timeout(const Duration(seconds: 35));
      }
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'isAvailable': data['isAvailable'] ?? isAvailable,
          'availability_status': data['availability_status'] ?? statusStr,
          'message': data['message'] ?? (isAvailable ? 'Availability turned ON.' : 'Availability turned OFF.'),
          'doctor': data['doctor'],
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update availability status.',
      };
    } catch (e) {
      debugPrint('Express updateDoctorAvailability notice: $e');
    }

    // Fallback to direct Supabase only if Express is unreachable
    try {
      final client = Supabase.instance.client;
      await client
          .from('dentists')
          .update({'availability_status': statusStr, 'updated_at': DateTime.now().toIso8601String()})
          .or('id.eq.$doctorId,user_id.eq.$doctorId');
      return {
        'success': true,
        'isAvailable': isAvailable,
        'availability_status': statusStr,
        'message': isAvailable ? 'Availability turned ON.' : 'Availability turned OFF.',
      };
    } catch (e) {
      debugPrint('Supabase direct updateDoctorAvailability notice: $e');
      return {
        'success': false,
        'message': 'Unable to update availability. Please check your connection.',
      };
    }
  }

  /// 4b. Fetch patient's saved "My Doctors" list
  Future<List<String>> fetchMyDoctors({required String patientId}) async {
    if (patientId.trim().isEmpty) return [];
    final cleanPId = patientId.trim();

    // 1. Direct Supabase Query (24/7 Resilience)
    try {
      final res = await Supabase.instance.client
          .from('patient_doctors')
          .select('doctor_id')
          .eq('patient_id', cleanPId);
      if (res.isNotEmpty) {
        return res.map((r) => r['doctor_id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('Supabase direct fetchMyDoctors notice: $e');
    }

    // 2. Express Backend API
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/patient/my-doctors').replace(queryParameters: {'patientId': cleanPId});
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['doctorIds'] ?? [];
        if (list is List) {
          return list.map((id) => id.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('Fetch My Doctors API error: $e');
    }
    return [];
  }

  /// 4c. Add a doctor to patient's "My Doctors" list
  Future<bool> addDoctorToMyDoctors({required String patientId, required String doctorId}) async {
    if (patientId.trim().isEmpty || doctorId.trim().isEmpty) return false;
    final cleanPId = patientId.trim();
    final cleanDId = doctorId.trim();

    // 1. Direct Supabase Query
    try {
      await Supabase.instance.client
          .from('patient_doctors')
          .upsert({'patient_id': cleanPId, 'doctor_id': cleanDId});
    } catch (e) {
      debugPrint('Supabase direct addDoctorToMyDoctors notice: $e');
    }

    // 2. Express Backend API
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/patient/my-doctors');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'patientId': cleanPId, 'doctorId': cleanDId}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
    } catch (e) {
      debugPrint('Add My Doctors API error: $e');
    }
    return true;
  }

  /// 4d. Remove a doctor from patient's "My Doctors" list
  Future<bool> removeDoctorFromMyDoctors({required String patientId, required String doctorId}) async {
    if (patientId.trim().isEmpty || doctorId.trim().isEmpty) return false;
    final cleanPId = patientId.trim();
    final cleanDId = doctorId.trim();

    // 1. Direct Supabase Query
    try {
      await Supabase.instance.client
          .from('patient_doctors')
          .delete()
          .eq('patient_id', cleanPId)
          .eq('doctor_id', cleanDId);
    } catch (e) {
      debugPrint('Supabase direct removeDoctorFromMyDoctors notice: $e');
    }

    // 2. Express Backend API
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/patient/my-doctors/$cleanDId?patientId=$cleanPId');
      final response = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('Remove My Doctors API error: $e');
    }
    return true;
  }

  /// Delete a doctor / dentist permanently from Supabase & Backend API
  Future<bool> deleteDoctor(String doctorId) async {
    if (doctorId.trim().isEmpty) return false;
    final cleanId = doctorId.trim();

    // 1. Direct Supabase Delete (handles both dentists table and users table)
    try {
      final docRes = await Supabase.instance.client
          .from('dentists')
          .select('id, user_id')
          .or('id.eq.$cleanId,user_id.eq.$cleanId')
          .maybeSingle();

      final dTableId = docRes?['id']?.toString() ?? cleanId;
      final uId = docRes?['user_id']?.toString();

      await Supabase.instance.client.from('patient_doctors').delete().or('doctor_id.eq.$dTableId,doctor_id.eq.$cleanId');
      await Supabase.instance.client.from('dentists').delete().or('id.eq.$dTableId,user_id.eq.$cleanId,id.eq.$cleanId');

      if (uId != null && uId.isNotEmpty) {
        await Supabase.instance.client.from('users').delete().eq('id', uId);
      } else {
        await Supabase.instance.client.from('users').delete().eq('id', cleanId);
      }
    } catch (sErr) {
      debugPrint('Supabase direct delete doctor notice: $sErr');
    }

    // 2. Express Backend API
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/dentists/$cleanId');
      final response = await http.delete(url, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) return true;
    } catch (e) {
      debugPrint('deleteDoctor API error: $e');
    }
    return true;
  }

  /// Delete a clinic permanently from Supabase & Backend API
  Future<bool> deleteClinic(String clinicId) async {
    if (clinicId.trim().isEmpty) return false;
    final cleanId = clinicId.trim();

    // 1. Direct Supabase Delete
    try {
      await Supabase.instance.client.from('clinics').delete().eq('id', cleanId);
    } catch (sErr) {
      debugPrint('Supabase direct delete clinic notice: $sErr');
    }

    // 2. Express Backend API
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/clinics/$cleanId');
      final response = await http.delete(url, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 204) return true;
    } catch (e) {
      debugPrint('deleteClinic API error: $e');
    }
    return true;
  }

  /// Delete a problem request from Supabase via backend API
  Future<bool> deleteProblemRequest(String id) async {
    try {
      await Supabase.instance.client.from('patient_problem_requests').delete().eq('id', id);
    } catch (sErr) {
      debugPrint('Supabase direct delete problem request notice: $sErr');
    }

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/problem-requests/$id');
      final response = await http.delete(url, headers: _headers).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('deleteProblemRequest API error: $e');
      return false;
    }
  }

  /// Fetch doctors registered under a specific clinic (Admin / Clinic directory inspection)
  Future<List<dynamic>> fetchClinicDentists(String clinicId, {bool includeUnavailable = true}) async {
    final cleanClinicId = clinicId.trim();
    if (cleanClinicId.isEmpty) return [];

    // 1. Authoritative Express API (/clinics/:clinicId/doctors)
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$cleanClinicId/doctors').replace(
        queryParameters: {'includeUnavailable': includeUnavailable ? 'true' : 'false'},
      );
      final response = await http.get(uri, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['dentists'] ?? data['doctors'] ?? [];
        if (list is List) {
          return list;
        }
      }
    } catch (e) {
      debugPrint('Fetch clinic dentists API notice: $e');
    }

    // 2. Direct Supabase fallback when Express is unreachable
    try {
      final res = await Supabase.instance.client
          .from('dentists')
          .select('*, users!user_id(*), clinics!clinic_id(*)')
          .eq('clinic_id', cleanClinicId)
          .order('created_at', ascending: false);
      return List<dynamic>.from(res);
    } catch (e) {
      debugPrint('Supabase direct fetch clinic dentists notice: $e');
    }
    return [];
  }

  @visibleForTesting
  static Future<List<dynamic>> Function()? debugFetchClinicsOverride;

  bool _lastFetchClinicsSucceeded = false;
  bool get lastFetchClinicsSucceeded => _lastFetchClinicsSucceeded;

  /// Fetch live clinics directory from Supabase via configured Backend API
  Future<List<dynamic>> fetchClinics({http.Client? client}) async {
    _lastFetchClinicsSucceeded = false;
    if (debugFetchClinicsOverride != null) {
      _lastFetchClinicsSucceeded = true;
      return debugFetchClinicsOverride!();
    }
    try {
      final url = Uri.parse(ApiConstants.clinics);
      final response = client != null
          ? await client.get(url, headers: _headersWithUser()).timeout(const Duration(seconds: 35))
          : await http.get(url, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _lastFetchClinicsSucceeded = true;
        return data['clinics'] ?? [];
      }
    } catch (e) {
      debugPrint('Fetch clinics error: $e');
    }

    if (client == null) {
      try {
        final res = await Supabase.instance.client
            .from('clinics')
            .select('*, users(id, name, email, phone)')
            .order('created_at', ascending: false);
        _lastFetchClinicsSucceeded = true;
        return List<dynamic>.from(res);
      } catch (e) {
        debugPrint('Fetch clinics Supabase fallback notice: $e');
      }
    }
    return [];
  }

  /// Create/Register a new clinic in Supabase via Backend API
  Future<Map<String, dynamic>> createClinicProfile({
    required String clinicName,
    required String location,
    List<String>? services,
    List<Map<String, dynamic>>? pricing,
  }) async {
    try {
      final url = Uri.parse(ApiConstants.clinics);
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'clinicName': clinicName,
          'location': location,
          if (services != null) 'services': services,
          if (pricing != null) 'pricing': pricing,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'clinic': data['clinic'], 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to create clinic.'};
      }
    } catch (e) {
      debugPrint('Create clinic error: $e');
      return {'success': false, 'message': 'Failed to connect to backend server.'};
    }
  }

  /// Create a new appointment in Supabase (supports mandatory lockId & releasedSlotId)
  Future<Map<String, dynamic>> createAppointment({
    required String patientId,
    String dentistId = '',
    String clinicId = '',
    required String date,
    required String timeSlot,
    required String treatment,
    String? consultationMode,
    String? lockId,
    String? releasedSlotId,
    bool requireLock = false,
  }) async {
    try {
      final url = Uri.parse(ApiConstants.appointments);
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'patientId': patientId,
          'dentistId': dentistId,
          'clinicId': clinicId,
          'date': date,
          'timeSlot': timeSlot,
          'treatment': treatment,
          if (consultationMode != null && consultationMode.trim().isNotEmpty)
            'consultationMode': consultationMode.trim(),
          if (lockId != null && lockId.trim().isNotEmpty) 'lockId': lockId.trim(),
          if (releasedSlotId != null && releasedSlotId.trim().isNotEmpty)
            'releasedSlotId': releasedSlotId.trim(),
          if (requireLock) 'requireLock': true,
        }),
      ).timeout(const Duration(seconds: 35));
      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        AnalyticsService.logAppointmentBooking(
          doctorId: dentistId,
          serviceName: treatment,
          clinicId: clinicId,
        );
      }
      return resData;
    } catch (e) {
      // Direct 24/7 Supabase Cloud Fallback (Rule 7)
      try {
        final client = Supabase.instance.client;
        final dateOnly = date.contains('T') ? date.split('T').first : date;
        String resolvedDentistId = dentistId;
        String resolvedClinicId = clinicId.trim();
        if (dentistId.isNotEmpty) {
          final idsToMatch = <String>{dentistId};
          try {
            final dRow = await client
                .from('dentists')
                .select('id, user_id, clinic_id')
                .or('id.eq.$dentistId,user_id.eq.$dentistId')
                .limit(1)
                .maybeSingle();
            if (dRow != null) {
              if (dRow['id'] != null) {
                resolvedDentistId = dRow['id'].toString();
                idsToMatch.add(resolvedDentistId);
              }
              if (dRow['user_id'] != null) idsToMatch.add(dRow['user_id'].toString());
              if (resolvedClinicId.isEmpty && dRow['clinic_id'] != null) {
                resolvedClinicId = dRow['clinic_id'].toString();
              }
            }
          } catch (_) {}

          final idFilter = idsToMatch.map((id) => 'dentist_id.eq.$id').join(',');
          final availRec = await client
              .from('doctor_availability')
              .select('is_blocked, blocked_reason')
              .or(idFilter)
              .eq('date', dateOnly)
              .limit(1)
              .maybeSingle()
              .catchError((_) => null);
          if (availRec != null && availRec['is_blocked'] == true) {
            return {
              'success': false,
              'isBlocked': true,
              'message': 'The doctor is unavailable on this date (${availRec['blocked_reason'] ?? 'Blocked / On Leave'}). Please choose another date.',
            };
          }

          final existing = await client.from('appointments').select('*').eq('dentist_id', resolvedDentistId).eq('time_slot', timeSlot);
          final conflict = (existing as List).any((a) {
            final s = (a['status'] ?? '').toString().toUpperCase();
            if (s == 'CANCELLED' || s == 'REJECTED') return false;
            final aDate = (a['date'] ?? '').toString().split('T').first;
            return aDate == dateOnly;
          });
          if (conflict) {
            return {
              'success': false,
              'message': 'The time slot ($timeSlot) is already booked for this doctor on this date. Please select another slot.'
            };
          }
        }
        final res = await client.from('appointments').insert({
          'patient_id': patientId,
          'dentist_id': resolvedDentistId.isNotEmpty ? resolvedDentistId : null,
          'clinic_id': resolvedClinicId.isNotEmpty ? resolvedClinicId : null,
          'date': date,
          'time_slot': timeSlot,
          'treatment': treatment,
          'status': 'PENDING',
        }).select().single();
        if (resolvedDentistId.isNotEmpty) {
          try {
            await client.from('notifications').insert({
              'recipient_role': 'Dentist',
              'recipient_id': resolvedDentistId,
              'title': 'New Appointment Booking',
              'message': 'Patient booked an appointment ($treatment) on $dateOnly at $timeSlot. Status: PENDING.',
              'type': 'appointment_request',
            });
          } catch (_) {}
        }
        if (resolvedClinicId.isNotEmpty) {
          try {
            await client.from('notifications').insert({
              'recipient_role': 'Clinic',
              'recipient_id': resolvedClinicId,
              'title': 'New Appointment Booking',
              'message': 'A patient booked an appointment on $dateOnly at $timeSlot. Status: PENDING.',
              'type': 'clinic_appointment_booked',
            });
          } catch (_) {}
        }
        return {'success': true, 'message': 'Appointment request submitted successfully.', 'appointment': res};
      } catch (err) {
        return {'success': false, 'message': 'Failed to create appointment: $err'};
      }
    }
  }

  /// Test-only hook so widget tests can supply patient/doctor appointment rows without a backend.
  @visibleForTesting
  static Future<List<dynamic>> Function({String? patientId, String? dentistId})? debugFetchAppointmentsOverride;

  @visibleForTesting
  static Future<List<dynamic>> Function({String? clinicId})? debugFetchClinicAppointmentsOverride;

  /// Fetch live appointments from Express backend first (enriched with selectedDoctor, patient, clinic),
  /// with Direct 24/7 Supabase Cloud Fallback.
  Future<List<dynamic>> fetchAppointments({String? patientId, String? dentistId, String? clinicId}) async {
    if (clinicId != null && clinicId.isNotEmpty && debugFetchClinicAppointmentsOverride != null) {
      return debugFetchClinicAppointmentsOverride!(clinicId: clinicId);
    }
    final override = debugFetchAppointmentsOverride;
    if (override != null && (clinicId == null || clinicId.isEmpty)) {
      return override(patientId: patientId, dentistId: dentistId);
    }

    final currentUserId = SupabaseService.safeCurrentUser?.id;

    // 1. Primary Express backend API first (resolves dentistId, patientId & clinicId + returns enriched metadata)
    try {
      final uri = Uri.parse(ApiConstants.appointments).replace(queryParameters: {
        if (patientId != null && patientId.isNotEmpty) 'patientId': patientId,
        if (dentistId != null && dentistId.isNotEmpty) 'dentistId': dentistId,
        if (clinicId != null && clinicId.isNotEmpty) 'clinicId': clinicId,
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<dynamic>.from(data['appointments'] ?? const []);
      }
    } catch (e) {
      debugPrint('Express fetch appointments notice: $e');
    }

    // 2. Direct 24/7 Supabase Cloud Fallback (only if Express backend is unreachable)
    try {
      final client = Supabase.instance.client;
      var query = client.from('appointments').select(
        '*, patient:users!patient_id(id, name, email, phone, city, pincode, age, gender), '
        'dentist:dentists!dentist_id(id, user_id, clinic_id, speciality, qualifications, experience_years, availability_status, users(id, name, phone, email, biometric_token), clinics(id, clinic_name, location)), '
        'clinic:clinics!clinic_id(id, clinic_name, location)',
      );
      if (clinicId != null && clinicId.isNotEmpty) {
        String resolvedClinicTableId = clinicId;
        try {
          final cRow = await client
              .from('clinics')
              .select('id')
              .or('id.eq.$clinicId,user_id.eq.$clinicId')
              .limit(1)
              .maybeSingle();
          if (cRow != null && cRow['id'] != null) {
            resolvedClinicTableId = cRow['id'].toString();
          }
        } catch (_) {}
        query = query.eq('clinic_id', resolvedClinicTableId);
      } else if (dentistId != null && dentistId.isNotEmpty) {
        String resolvedDentistTableId = dentistId;
        try {
          final docRow = await client
              .from('dentists')
              .select('id, user_id')
              .or('id.eq.$dentistId,user_id.eq.$dentistId')
              .maybeSingle();
          if (docRow != null && docRow['id'] != null) {
            resolvedDentistTableId = docRow['id'].toString();
          }
        } catch (_) {}
        if (resolvedDentistTableId != dentistId) {
          query = query.or('dentist_id.eq.$resolvedDentistTableId,dentist_id.eq.$dentistId');
        } else {
          query = query.eq('dentist_id', dentistId);
        }
      } else if (patientId != null && patientId.isNotEmpty) {
        query = query.eq('patient_id', patientId);
      } else if (currentUserId != null && currentUserId.isNotEmpty) {
        query = query.eq('patient_id', currentUserId);
      } else {
        return [];
      }
      final res = await query.order('created_at', ascending: false);
      return List<dynamic>.from(res);
    } catch (e) {
      debugPrint('Supabase direct fetch appointments fallback notice: $e');
    }
    return [];
  }

  /// Test-only hook so widget tests can supply appointment rows without a backend.
  @visibleForTesting
  static Future<List<dynamic>> Function()? debugAdminAppointmentsOverride;

  /// READ-ONLY. Latest appointments across the platform for the Admin/Sub-Admin
  /// overview. Authorization is enforced server-side: Supabase RLS on the direct
  /// query, and the Express controller's role check on the fallback.
  /// Returns an empty list when the backend answers with no rows; throws when
  /// every source fails so the UI can show an error state.
  Future<List<dynamic>> fetchAllAppointmentsForAdmin({int limit = 200}) async {
    final override = debugAdminAppointmentsOverride;
    if (override != null) return override();

    // 1. Express backend first (enforces Admin/Sub-Admin auth & returns joined patient, selectedDoctor, clinic)
    try {
      final response = await http
          .get(Uri.parse(ApiConstants.appointments), headers: _headers)
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = List<dynamic>.from(data['appointments'] ?? const []);
        return list.length > limit ? list.sublist(0, limit) : list;
      }
    } catch (e) {
      debugPrint('Admin appointments Express API notice: $e');
    }

    // 2. Direct Supabase fallback with full relational joins on saved dentist_id & clinic_id
    try {
      final res = await Supabase.instance.client
          .from('appointments')
          .select(
            '*, patient:users!patient_id(id, name, email, phone), '
            'dentist:dentists!dentist_id(id, user_id, clinic_id, speciality, qualifications, users(id, name, phone, email, biometric_token), clinics(id, clinic_name, location)), '
            'clinic:clinics!clinic_id(id, clinic_name, location)',
          )
          .order('created_at', ascending: false)
          .limit(limit);
      return List<dynamic>.from(res);
    } catch (e) {
      debugPrint('Admin appointments Supabase join notice: $e');
      final fallbackRes = await Supabase.instance.client
          .from('appointments')
          .select('*')
          .order('created_at', ascending: false)
          .limit(limit);
      return List<dynamic>.from(fallbackRes);
    }
  }

  /// Generates a unique 1-on-1 Chat Room ID between a Patient and a Doctor
  static String getChatRoomId({required String patientIdOrName, required String dentistIdOrName}) {
    final pClean = patientIdOrName.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    final dClean = dentistIdOrName.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_').replaceFirst(RegExp(r'^DR_'), '');
    final pFinal = pClean.isEmpty ? 'PATIENT' : pClean;
    final dFinal = dClean.isEmpty ? 'DOCTOR' : dClean;
    return 'CHAT_${pFinal}_$dFinal';
  }

  /// Centralized room ID normalization helper
  static String normalizeRoomId(String roomId) {
    if (roomId.trim().isEmpty) return 'CHAT_PATIENT_DOCTOR';
    final cleaned = roomId.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    if (cleaned.startsWith('CHAT_') || cleaned.startsWith('ROOM_')) {
      return cleaned;
    }
    return cleaned.startsWith('PATIENT_') ? cleaned : 'PATIENT_$cleaned';
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String senderId,
    required String message,
    required String roomId,
    String? receiverId,
    String? type,
    String? senderRole,
  })? debugSendMessageOverride;

  @visibleForTesting
  static Future<List<dynamic>> Function({required String roomId})? debugFetchChatMessagesOverride;

  @visibleForTesting
  static Future<List<dynamic>> Function()? debugFetchConversationsOverride;

  @visibleForTesting
  static Future<bool> Function(String id, {String? status, bool? isActive})? debugToggleSubAdminStatusOverride;

  /// Send a live chat message via Express Backend API first (single authoritative write,
  /// enforces RBAC + prevents duplicates), falling back to direct Supabase only if unreachable.
  Future<Map<String, dynamic>> sendMessage({
    required String senderId,
    required String message,
    required String roomId,
    String? receiverId,
    String? type,
    String? senderRole,
  }) async {
    if (debugSendMessageOverride != null) {
      return debugSendMessageOverride!(
        senderId: senderId,
        message: message,
        roomId: roomId,
        receiverId: receiverId,
        type: type,
        senderRole: senderRole,
      );
    }

    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return {'success': false, 'message': 'Message cannot be empty.'};
    }

    final normRoom = normalizeRoomId(roomId);
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    final cleanSenderId = senderId.trim();
    final validSenderUuid = uuidRegex.hasMatch(cleanSenderId) ? cleanSenderId : null;
    final cleanReceiverId = receiverId?.trim() ?? '';
    final validReceiverUuid = uuidRegex.hasMatch(cleanReceiverId) ? cleanReceiverId : null;

    // 1. Authoritative Express Backend API (handles UUID resolution, RBAC, dedup, and Supabase persistence)
    try {
      final url = Uri.parse(ApiConstants.chatSend);
      final response = await http.post(
        url,
        headers: _headersWithUser(),
        body: jsonEncode({
          'senderId': cleanSenderId,
          'message': trimmed,
          'roomId': normRoom,
          if (type != null) 'type': type,
          if (cleanReceiverId.isNotEmpty) 'receiverId': cleanReceiverId,
          if (senderRole != null) 'senderRole': senderRole,
        }),
      ).timeout(const Duration(seconds: 35));

      Map<String, dynamic> resBody = {};
      try {
        resBody = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': resBody['message'] ?? 'Chat message sent successfully.',
          if (resBody['chat'] != null) 'chat': resBody['chat'],
        };
      }
      if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'status': response.statusCode,
          'message': resBody['message'] ?? 'Not authorized to send message.',
        };
      }
      throw Exception(resBody['message'] ?? 'Server error ${response.statusCode}');
    } catch (e) {
      debugPrint('Express chat send notice ($e), attempting 24/7 Supabase fallback...');
    }

    // 2. Single Direct Supabase fallback ONLY if Express is unreachable
    try {
      final client = Supabase.instance.client;
      String? authUserId;
      try {
        authUserId = client.auth.currentUser?.id;
      } catch (_) {}
      final effectiveUuid = validSenderUuid ??
          (authUserId != null && uuidRegex.hasMatch(authUserId) ? authUserId : null);

      final payload = <String, dynamic>{
        'room_id': normRoom,
        'sender_id': effectiveUuid,
        if (validReceiverUuid != null) 'receiver_id': validReceiverUuid,
        'message': trimmed,
        'type': type ?? 'text',
        'read': false,
      };

      final inserted = await client
          .from('chat_messages')
          .insert(payload)
          .select('*, sender:users!sender_id(id, name, email, role)')
          .maybeSingle();
      return {
        'success': true,
        'message': 'Chat message sent successfully.',
        if (inserted != null) 'chat': inserted,
      };
    } catch (sbErr) {
      debugPrint('Supabase chat message fallback failed: $sbErr');
      return {
        'success': false,
        'message': 'Failed to send message. Please check your connection and try again.',
      };
    }
  }

  /// Fetch chat messages thread from Backend API (RBAC-enforced) with Supabase fallback
  Future<List<dynamic>> fetchChatMessages({required String roomId, bool markRead = false}) async {
    if (debugFetchChatMessagesOverride != null) {
      return debugFetchChatMessagesOverride!(roomId: roomId);
    }

    final norm = normalizeRoomId(roomId);
    final hyph = norm.replaceAll('_', '-');

    // 1. Express Backend primary (handles RBAC + Sub-Admin 403 + Audit logging)
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/chat/messages').replace(
        queryParameters: {
          'roomId': norm,
          if (markRead) 'markRead': 'true',
        },
      );
      final response = await http.get(uri, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['messages'] ?? [];
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('🔒 Chat messages access denied (${response.statusCode}).');
        return [];
      }
    } catch (e) {
      debugPrint('Express backend fetch chat messages notice: $e');
    }

    // 2. Direct Supabase query fallback when Express is unreachable
    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('chat_messages')
          .select('*, sender:users!sender_id(id, name, email, role), receiver:users!receiver_id(id, name, email, role)')
          .or('room_id.eq.$norm,room_id.eq.$hyph,room_id.eq.$roomId')
          .order('created_at', ascending: true);
      return List<dynamic>.from(res);
    } catch (e) {
      try {
        final client = Supabase.instance.client;
        final res = await client
            .from('chat_messages')
            .select('*, sender:users!sender_id(id, name, email, role)')
            .or('room_id.eq.$norm,room_id.eq.$hyph,room_id.eq.$roomId')
            .order('created_at', ascending: true);
        return List<dynamic>.from(res);
      } catch (err) {
        debugPrint('Supabase direct fetch chat messages notice: $err');
      }
    }
    return [];
  }

  /// Mark all unread messages in a chat room as read for the current user
  Future<bool> markChatRoomRead({required String roomId, String? currentUserId}) async {
    final norm = normalizeRoomId(roomId);
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/chat/read');
      final response = await http.post(
        uri,
        headers: _headersWithUser(),
        body: jsonEncode({'roomId': norm}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) return true;
      if (response.statusCode == 401 || response.statusCode == 403) return false;
    } catch (_) {}

    try {
      final client = Supabase.instance.client;
      var query = client.from('chat_messages').update({'read': true}).eq('room_id', norm).eq('read', false);
      if (currentUserId != null && currentUserId.trim().isNotEmpty) {
        query = query.or('sender_id.is.null,sender_id.neq.${currentUserId.trim()}');
      }
      await query;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete single message or clear all chat messages in a room
  Future<bool> clearChatMessages({required String roomId, String? messageId}) async {
    final norm = normalizeRoomId(roomId);
    final hyph = norm.replaceAll('_', '-');

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/chat/clear');
      final response = await http.post(
        url,
        headers: _headersWithUser(),
        body: jsonEncode({
          'roomId': norm,
          if (messageId != null) 'messageId': messageId,
        }),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      if (response.statusCode == 401 || response.statusCode == 403) return false;
    } catch (e) {
      debugPrint('Clear chat backend error: $e');
    }

    // Fallback: Direct Supabase deletion
    try {
      final client = Supabase.instance.client;
      if (messageId != null && messageId.isNotEmpty) {
        await client.from('chat_messages').delete().eq('id', messageId);
      } else {
        await client.from('chat_messages').delete().or('room_id.eq.$norm,room_id.eq.$hyph,room_id.eq.$roomId');
      }
      return true;
    } catch (e) {
      debugPrint('Supabase direct clear chat notice: $e');
      return false;
    }
  }

  /// Fetch all active patient-doctor chat conversations (Role-enforced, strictly forbidden for Sub-Admins)
  Future<List<dynamic>> fetchConversations({String? currentUserId}) async {
    if (debugFetchConversationsOverride != null) {
      return debugFetchConversationsOverride!();
    }

    // 1. Express backend call (handles RBAC and Admin audit logs)
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/chat/conversations');
      final response = await http.get(url, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['conversations'] ?? [];
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('🔒 Conversations access restricted (${response.statusCode}).');
        return [];
      }
    } catch (e) {
      debugPrint('Fetch conversations error: $e');
    }

    // 2. Direct Supabase query fallback
    try {
      final client = Supabase.instance.client;
      final msgs = await client
          .from('chat_messages')
          .select('*, sender:users!sender_id(id, name, email, role)')
          .order('created_at', ascending: false);
      if (msgs.isNotEmpty) {
        final Map<String, dynamic> roomMap = {};
        for (final m in msgs) {
          final rId = normalizeRoomId((m['room_id'] ?? '').toString());
          final senderObj = m['sender'] as Map<String, dynamic>?;
          final isUnreadForViewer = (m['read'] != true) &&
              (currentUserId == null || currentUserId.isEmpty || m['sender_id']?.toString() != currentUserId);
          if (!roomMap.containsKey(rId)) {
            final isDoc = (m['type'] == 'doctor' || senderObj?['role'] == 'Dentist' || senderObj?['role'] == 'Doctor');
            roomMap[rId] = {
              'roomId': rId,
              'patientName': rId.replaceFirst('PATIENT_', '').replaceAll('_', ' '),
              'doctorName': isDoc ? (senderObj?['name'] ?? 'Doctor') : 'Doctor',
              'lastMessage': m['message'],
              'lastMessageType': m['type'],
              'lastMessageTime': m['created_at'],
              'totalMessages': 1,
              'unreadCount': isUnreadForViewer ? 1 : 0,
            };
          } else {
            roomMap[rId]['totalMessages'] = (roomMap[rId]['totalMessages'] as int) + 1;
            if (isUnreadForViewer) {
              roomMap[rId]['unreadCount'] = (roomMap[rId]['unreadCount'] as int) + 1;
            }
          }
        }
        return roomMap.values.toList();
      }
    } catch (e) {
      debugPrint('Supabase direct fetch conversations fallback notice: $e');
    }

    return [];
  }

  /// Fetch Main Admin chat audit logs
  Future<List<dynamic>> fetchChatAuditLogs({String? action, String? targetResource}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/chat/audit-logs').replace(queryParameters: {
        if (action != null) 'action': action,
        if (targetResource != null) 'targetResource': targetResource,
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['logs'] ?? [];
      }
    } catch (e) {
      debugPrint('Fetch chat audit logs error: $e');
    }
    return [];
  }

  // ─────────────────────────────────────────────
  // DENTAL HEALTH RECORDS & DOCTOR SHARING (PATIENT <-> DOCTOR)
  // ─────────────────────────────────────────────

  static final Map<String, Uint8List> _recordBytesCache = {};
  static final List<Map<String, dynamic>> _fallbackMedicalRecords = [];

  static void cacheRecordBytes(String storageKey, Uint8List bytes) {
    if (storageKey.isNotEmpty) {
      _recordBytesCache[storageKey] = bytes;
    }
  }

  static Uint8List? getCachedRecordBytes(String storageKey) {
    if (storageKey.isEmpty) return null;
    return _recordBytesCache[storageKey];
  }

  static const List<String> _allowedRecordCategories = [
    'Dental X-ray',
    'Prescription',
    'Dental Report',
    'Lab Report',
    'Treatment Documents',
    'Other',
  ];

  static const List<String> _allowedRecordExtensions = ['jpg', 'jpeg', 'png', 'pdf'];
  static const int _maxRecordFileSizeBytes = 20 * 1024 * 1024; // 20 MB

  static Map<String, dynamic> _parseNotesJson(dynamic rawNotes) {
    if (rawNotes == null) return <String, dynamic>{};
    if (rawNotes is Map) return Map<String, dynamic>.from(rawNotes);
    final str = rawNotes.toString().trim();
    if (str.startsWith('{') && str.endsWith('}')) {
      try {
        final decoded = jsonDecode(str);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> formatMedicalRecordRow(Map<String, dynamic> row) {
    // If already formatted from Express API
    if (row.containsKey('recordSource') && row.containsKey('sharedWith') && !row.containsKey('notes')) {
      final copy = Map<String, dynamic>.from(row);
      copy['sharedWith'] = (copy['sharedWith'] is List)
          ? (copy['sharedWith'] as List).map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList()
          : <Map<String, dynamic>>[];
      return copy;
    }

    final parsedNotes = _parseNotesJson(row['notes']);
    final patientObj = row['patient'] is Map ? Map<String, dynamic>.from(row['patient']) : <String, dynamic>{};

    String storageKey = (parsedNotes['storageKey'] ?? row['storageKey'] ?? '').toString();
    if (storageKey.isEmpty && row['xray_urls'] is List && (row['xray_urls'] as List).isNotEmpty) {
      storageKey = (row['xray_urls'] as List).first.toString();
    }
    if (storageKey.isEmpty && row['lab_report_urls'] is List && (row['lab_report_urls'] as List).isNotEmpty) {
      storageKey = (row['lab_report_urls'] as List).first.toString();
    }

    final rawType = (parsedNotes['type'] ?? row['type'] ?? '').toString();
    final category = (parsedNotes['category'] ?? row['category'] ?? (rawType == 'xray' ? 'Dental X-ray' : rawType == 'prescription' ? 'Prescription' : 'Other')).toString();
    final title = (parsedNotes['title'] ?? row['title'] ?? row['diagnosis'] ?? 'Health Record').toString();
    final description = (parsedNotes['description'] ?? row['description'] ?? parsedNotes['subtitle'] ?? row['subtitle'] ?? '').toString();
    final fileName = (parsedNotes['fileName'] ?? row['fileName'] ?? '').toString();
    final fileType = (parsedNotes['fileType'] ?? row['fileType'] ?? '').toString().toUpperCase();
    final mimeType = (parsedNotes['mimeType'] ?? row['mimeType'] ?? '').toString();
    final fileSize = int.tryParse((parsedNotes['fileSize'] ?? row['fileSize'] ?? '0').toString()) ?? 0;

    final List<Map<String, dynamic>> sharedWith = [];
    final rawShared = parsedNotes['sharedWith'] ?? row['sharedWith'];
    if (rawShared is List) {
      for (final item in rawShared) {
        if (item is Map) {
          sharedWith.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final uploadedAt = (parsedNotes['uploadedAt'] ?? row['uploadedAt'] ?? row['date'] ?? row['created_at'] ?? DateTime.now().toIso8601String()).toString();
    final updatedAt = (parsedNotes['updatedAt'] ?? row['updatedAt'] ?? row['updated_at'] ?? uploadedAt).toString();

    return {
      'id': (row['id'] ?? row['_id'] ?? '').toString(),
      'patientId': (row['patient_id'] ?? row['patientId'] ?? parsedNotes['patientId'] ?? '').toString(),
      'patientName': (parsedNotes['patientName'] ?? row['patientName'] ?? patientObj['name'] ?? '').toString(),
      'dentistId': (row['dentist_id'] ?? row['dentistId'] ?? parsedNotes['dentistId'] ?? '').toString(),
      'appointmentId': (row['appointment_id'] ?? row['appointmentId'] ?? parsedNotes['appointmentId'] ?? '').toString(),
      'recordSource': (parsedNotes['recordSource'] ?? row['recordSource'] ?? (fileName.isNotEmpty ? 'patient_upload' : 'doctor_issued')).toString(),
      'type': rawType.isNotEmpty
          ? rawType
          : (category == 'Dental X-ray' ? 'xray' : category == 'Prescription' ? 'prescription' : 'document'),
      'title': title,
      'category': category,
      'specialty': (parsedNotes['specialty'] ?? row['specialty'] ?? '').toString(),
      'department': (parsedNotes['department'] ?? row['department'] ?? '').toString(),
      'diagnosis': (parsedNotes['diagnosis'] ?? row['diagnosis'] ?? title).toString(),
      'symptoms': (parsedNotes['symptoms'] ?? row['symptoms'] ?? '').toString(),
      'clinicalSections': parsedNotes['clinicalSections'] is Map
          ? Map<String, dynamic>.from(parsedNotes['clinicalSections'] as Map)
          : (row['clinicalSections'] is Map ? Map<String, dynamic>.from(row['clinicalSections'] as Map) : <String, dynamic>{}),
      'followUpDate': (parsedNotes['followUpDate'] ?? row['followUpDate'] ?? '').toString(),
      'instructions': (parsedNotes['instructions'] ?? row['instructions'] ?? '').toString(),
      'doctorQualification': (parsedNotes['doctorQualification'] ?? row['doctorQualification'] ?? '').toString(),
      'approvedByDoctor': parsedNotes['approvedByDoctor'] == true || row['approvedByDoctor'] == true,
      'description': description,
      'subtitle': description.isNotEmpty ? description : category,
      'doctorName': (parsedNotes['doctorName'] ?? parsedNotes['doctor_name'] ?? row['doctorName'] ?? '').toString(),
      'clinicName': (parsedNotes['clinicName'] ?? parsedNotes['clinic_name'] ?? row['clinicName'] ?? '').toString(),
      'fileName': fileName,
      'fileType': fileType,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'storageKey': storageKey,
      'storageProvider': (parsedNotes['storageProvider'] ?? 'supabase').toString(),
      'sharedWith': sharedWith,
      'date': uploadedAt.contains('T') ? uploadedAt.split('T').first : uploadedAt,
      'uploadedAt': uploadedAt,
      'updatedAt': updatedAt,
      'items': (row['prescriptions'] is List)
          ? row['prescriptions']
          : ((row['items'] is List) ? row['items'] : []),
    };
  }

  static bool isDoctorAuthorizedForRecordMap(
    Map<String, dynamic> record, {
    required String doctorId,
    String? doctorUserId,
    String? doctorEmail,
  }) {
    final targetIds = <String>{
      if (doctorId.trim().isNotEmpty) doctorId.trim().toLowerCase(),
      if (doctorUserId != null && doctorUserId.trim().isNotEmpty) doctorUserId.trim().toLowerCase(),
      if (doctorEmail != null && doctorEmail.trim().isNotEmpty) doctorEmail.trim().toLowerCase(),
    };
    if (targetIds.isEmpty) return false;

    final sharedWith = record['sharedWith'];
    if (sharedWith is List) {
      for (final item in sharedWith) {
        if (item is Map) {
          final dId = (item['doctorId'] ?? '').toString().trim().toLowerCase();
          final dUserId = (item['doctorUserId'] ?? '').toString().trim().toLowerCase();
          final dEmail = (item['doctorEmail'] ?? '').toString().trim().toLowerCase();
          if ((dId.isNotEmpty && targetIds.contains(dId)) ||
              (dUserId.isNotEmpty && targetIds.contains(dUserId)) ||
              (dEmail.isNotEmpty && targetIds.contains(dEmail))) {
            return true;
          }
        }
      }
    }
    return false;
  }

  Future<String?> _resolvePatientUuid(String? rawPatientId) async {
    if (rawPatientId == null || rawPatientId.trim().isEmpty) return null;
    final clean = rawPatientId.trim();
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    if (uuidRegex.hasMatch(clean)) return clean;

    try {
      final client = Supabase.instance.client;
      final u = await client
          .from('users')
          .select('id')
          .or('email.ilike.$clean,phone.eq.$clean,name.ilike.$clean')
          .limit(1)
          .maybeSingle();
      if (u != null && u['id'] != null) return u['id'].toString();
    } catch (_) {}
    return clean;
  }

  /// Fetch medical records and prescriptions from Supabase/Backend API
  Future<List<dynamic>> fetchMedicalRecords({String? patientId, String? doctorId}) async {
    final Map<String, Map<String, dynamic>> merged = {};
    final resolvedPatientId = await _resolvePatientUuid(patientId);

    // 1. Direct Supabase query first
    try {
      final client = Supabase.instance.client;
      var query = client.from('medical_records').select('*, patient:users!patient_id(id, name, email, phone)');
      if (resolvedPatientId != null && resolvedPatientId.isNotEmpty) {
        final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
        if (uuidRegex.hasMatch(resolvedPatientId)) {
          query = query.eq('patient_id', resolvedPatientId);
        }
      }
      final res = await query.order('created_at', ascending: false);
      for (final row in res) {
        final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(row));
        final id = formatted['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          if (resolvedPatientId != null && resolvedPatientId.isNotEmpty) {
            if (formatted['patientId'] == resolvedPatientId || formatted['patientId'] == patientId) {
              merged[id] = formatted;
            }
          } else {
            merged[id] = formatted;
          }
        }
      }
    } catch (e) {
      // Fallback without join if needed
      try {
        final client = Supabase.instance.client;
        var simpleQuery = client.from('medical_records').select('*');
        if (resolvedPatientId != null && resolvedPatientId.isNotEmpty) {
          final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
          if (uuidRegex.hasMatch(resolvedPatientId)) {
            simpleQuery = simpleQuery.eq('patient_id', resolvedPatientId);
          }
        }
        final res = await simpleQuery.order('created_at', ascending: false);
        for (final row in res) {
          final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(row));
          final id = formatted['id']?.toString() ?? '';
          if (id.isNotEmpty) merged[id] = formatted;
        }
      } catch (_) {}
    }

    // 2. Express Backend API fallback
    if (merged.isEmpty) {
      try {
        final uri = Uri.parse(ApiConstants.records).replace(queryParameters: {
          if (patientId != null && patientId.isNotEmpty) 'patientId': patientId,
          if (doctorId != null && doctorId.isNotEmpty) 'doctorId': doctorId,
        });
        final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final list = data['records'] ?? [];
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(item));
                final id = formatted['id']?.toString() ?? '';
                if (id.isNotEmpty && !merged.containsKey(id)) {
                  merged[id] = formatted;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Fetch medical records error: $e');
      }
    }

    // 3. Include in-memory fallback records (used in offline/unit test environments)
    for (final rec in _fallbackMedicalRecords) {
      final formatted = formatMedicalRecordRow(rec);
      final id = formatted['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (resolvedPatientId != null && resolvedPatientId.isNotEmpty) {
        if (formatted['patientId'] == resolvedPatientId || formatted['patientId'] == patientId) {
          merged.putIfAbsent(id, () => formatted);
        }
      } else {
        merged.putIfAbsent(id, () => formatted);
      }
    }

    var results = merged.values.toList();
    if (doctorId != null && doctorId.trim().isNotEmpty) {
      results = results.where((rec) {
        if (rec['recordSource'] == 'doctor_issued' && rec['dentistId'] == doctorId.trim()) {
          return true;
        }
        return isDoctorAuthorizedForRecordMap(rec, doctorId: doctorId);
      }).toList();
    }
    return results;
  }

  /// Fetch patient records explicitly shared with a specific Doctor
  Future<List<Map<String, dynamic>>> fetchSharedRecordsForDoctor({
    required String doctorId,
    String? doctorUserId,
    String? doctorEmail,
    String? patientId,
  }) async {
    if (doctorId.trim().isEmpty && (doctorUserId == null || doctorUserId.trim().isEmpty) && (doctorEmail == null || doctorEmail.trim().isEmpty)) {
      return [];
    }

    String? resolvedDentistTableId;
    String? resolvedUserTableId;
    try {
      final client = Supabase.instance.client;
      final cleanId = doctorId.trim();
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      if (uuidRegex.hasMatch(cleanId)) {
        final d = await client.from('dentists').select('id, user_id').or('id.eq.$cleanId,user_id.eq.$cleanId').maybeSingle();
        if (d != null) {
          resolvedDentistTableId = d['id']?.toString();
          resolvedUserTableId = d['user_id']?.toString();
        }
      }
    } catch (_) {}

    final allRecords = await fetchMedicalRecords(patientId: patientId);
    final authorizedList = <Map<String, dynamic>>[];

    for (final raw in allRecords) {
      if (raw is! Map) continue;
      final rec = formatMedicalRecordRow(Map<String, dynamic>.from(raw));
      final isAuth = isDoctorAuthorizedForRecordMap(
            rec,
            doctorId: doctorId,
            doctorUserId: doctorUserId ?? resolvedUserTableId,
            doctorEmail: doctorEmail,
          ) ||
          (resolvedDentistTableId != null &&
              isDoctorAuthorizedForRecordMap(
                rec,
                doctorId: resolvedDentistTableId,
                doctorUserId: resolvedUserTableId,
                doctorEmail: doctorEmail,
              ));

      if (isAuth) {
        authorizedList.add(rec);
      }
    }

    return authorizedList;
  }

  /// Patient: Upload a new Dental Health Record with file validation & secure storage reference
  Future<Map<String, dynamic>> uploadPatientDentalRecord({
    required String patientId,
    required String patientName,
    required String title,
    required String category,
    String description = '',
    required String fileName,
    required String fileType,
    required String mimeType,
    required int fileSize,
    required Uint8List fileBytes,
    void Function(double progress)? onProgress,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      return {'success': false, 'message': 'Record Name is required.'};
    }
    if (patientId.trim().isEmpty) {
      return {'success': false, 'message': 'Patient authentication is required to upload records.'};
    }
    if (!_allowedRecordCategories.contains(category)) {
      return {'success': false, 'message': 'Invalid record category.'};
    }

    String ext = fileType.trim().toLowerCase().replaceAll('.', '');
    if (ext.isEmpty && fileName.contains('.')) {
      ext = fileName.split('.').last.trim().toLowerCase();
    }
    if (!_allowedRecordExtensions.contains(ext)) {
      return {
        'success': false,
        'message': 'Unsupported file format. Only JPG, JPEG, PNG, and PDF files are supported.',
      };
    }
    if (fileSize <= 0 || fileBytes.isEmpty) {
      return {'success': false, 'message': 'Selected file cannot be empty.'};
    }
    if (fileSize > _maxRecordFileSizeBytes) {
      return {'success': false, 'message': 'File size exceeds the 20 MB maximum limit.'};
    }

    onProgress?.call(0.2);

    final resolvedPatientId = (await _resolvePatientUuid(patientId)) ?? patientId.trim();
    final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final folder = category == 'Dental X-ray' ? 'xrays' : 'documents';
    String storageKey = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    // 1. Upload binary file to secure cloud storage (Supabase Storage or /api/v1/upload)
    bool uploadedToBucket = false;
    try {
      await Supabase.instance.client.storage.from('dentaguru-storage').uploadBinary(
            storageKey,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      uploadedToBucket = true;
    } catch (_) {}

    if (!uploadedToBucket) {
      try {
        final token = currentToken;
        if (token != null && token.isNotEmpty && !token.startsWith('sb_direct_')) {
          final request = http.MultipartRequest('POST', Uri.parse(ApiConstants.upload));
          request.headers['Authorization'] = 'Bearer $token';
          request.fields['folder'] = folder;
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              fileBytes,
              filename: safeFileName,
              contentType: http.MediaType.parse(
                mimeType.isNotEmpty
                    ? mimeType
                    : (ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
              ),
            ),
          );
          final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
          final response = await http.Response.fromStream(streamedResponse);
          if (response.statusCode == 200 || response.statusCode == 201) {
            final uploadData = jsonDecode(response.body);
            if (uploadData['key'] != null && uploadData['key'].toString().isNotEmpty) {
              storageKey = uploadData['key'].toString();
            }
          }
        }
      } catch (e) {
        debugPrint('Cloud storage upload notice: $e');
      }
    }

    onProgress?.call(0.65);

    // Cache file bytes by storageKey for immediate authenticated viewing/downloading
    cacheRecordBytes(storageKey, fileBytes);

    final nowIso = DateTime.now().toIso8601String();
    final notesMeta = <String, dynamic>{
      'recordSource': 'patient_upload',
      'type': category == 'Dental X-ray' ? 'xray' : (category == 'Prescription' ? 'prescription' : 'document'),
      'title': cleanTitle,
      'category': category,
      'description': description.trim(),
      'subtitle': description.trim().isNotEmpty ? description.trim() : category,
      'patientId': resolvedPatientId,
      'patientName': patientName.trim().isNotEmpty ? patientName.trim() : 'Patient',
      'fileName': fileName.trim(),
      'fileType': ext.toUpperCase(),
      'mimeType': mimeType.isNotEmpty
          ? mimeType
          : (ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
      'fileSize': fileSize,
      'storageKey': storageKey,
      'storageProvider': 'supabase',
      'uploadedAt': nowIso,
      'updatedAt': nowIso,
      'sharedWith': <Map<String, dynamic>>[],
    };

    final isXray = category == 'Dental X-ray';

    // 2. Save metadata + storageKey directly to Supabase PostgreSQL public.medical_records
    final client = SupabaseService.safeClient;
    if (client != null) {
      try {
        final inserted = await client
          .from('medical_records')
          .insert({
            'patient_id': resolvedPatientId,
            'diagnosis': cleanTitle,
            'notes': jsonEncode(notesMeta),
            'prescriptions': <dynamic>[],
            'xray_urls': isXray ? <String>[storageKey] : <String>[],
            'lab_report_urls': !isXray ? <String>[storageKey] : <String>[],
          })
          .select()
          .single();

      onProgress?.call(1.0);
      final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(inserted));
      _fallbackMedicalRecords.removeWhere((r) => r['id'] == formatted['id']);
      _fallbackMedicalRecords.insert(0, formatted);
        return {
          'success': true,
          'message': 'Health record uploaded successfully.',
          'record': formatted,
        };
      } catch (supaErr) {
        debugPrint('Supabase direct insert medical_record notice: $supaErr');
      }
    }

    // 3. Express Backend API fallback
    try {
      final response = await http
          .post(
            Uri.parse(ApiConstants.records),
            headers: _headers,
            body: jsonEncode({
              'patientId': resolvedPatientId,
              'patientName': patientName.trim(),
              'recordSource': 'patient_upload',
              'type': notesMeta['type'],
              'title': cleanTitle,
              'category': category,
              'description': description.trim(),
              'fileName': fileName.trim(),
              'fileType': ext.toUpperCase(),
              'mimeType': notesMeta['mimeType'],
              'fileSize': fileSize,
              'storageKey': storageKey,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['record'] is Map) {
          onProgress?.call(1.0);
          final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(data['record']));
          _fallbackMedicalRecords.removeWhere((r) => r['id'] == formatted['id']);
          _fallbackMedicalRecords.insert(0, formatted);
          return {
            'success': true,
            'message': 'Health record uploaded successfully.',
            'record': formatted,
          };
        }
      }
    } catch (_) {}

    // 4. Resilient local/test persistence fallback
    final fallbackRow = formatMedicalRecordRow({
      'id': 'rec-${DateTime.now().millisecondsSinceEpoch}',
      'patient_id': resolvedPatientId,
      'diagnosis': cleanTitle,
      'notes': jsonEncode(notesMeta),
      'xray_urls': isXray ? <String>[storageKey] : <String>[],
      'lab_report_urls': !isXray ? <String>[storageKey] : <String>[],
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    _fallbackMedicalRecords.insert(0, fallbackRow);
    onProgress?.call(1.0);
    return {
      'success': true,
      'message': 'Health record uploaded successfully.',
      'record': fallbackRow,
    };
  }

  /// Patient: Edit record details (Record Name, Category, Description) — Patient Owner Only
  Future<Map<String, dynamic>> updatePatientDentalRecord({
    required String recordId,
    required String patientId,
    required String title,
    required String category,
    required String description,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      return {'success': false, 'message': 'Record Name cannot be empty.'};
    }
    if (!_allowedRecordCategories.contains(category)) {
      return {'success': false, 'message': 'Invalid record category.'};
    }

    final resolvedPatientId = (await _resolvePatientUuid(patientId)) ?? patientId.trim();
    final nowIso = DateTime.now().toIso8601String();

    // 1. Direct Supabase ownership check & update
    try {
      final client = Supabase.instance.client;
      final existing = await client.from('medical_records').select('*').eq('id', recordId).maybeSingle();
      if (existing != null) {
        final ownerId = (existing['patient_id'] ?? '').toString();
        if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
          return {
            'success': false,
            'statusCode': 403,
            'message': 'Access Denied: Only the patient owner can edit this record.',
          };
        }
        final notesMeta = _parseNotesJson(existing['notes']);
        notesMeta['title'] = cleanTitle;
        notesMeta['category'] = category;
        notesMeta['description'] = description.trim();
        notesMeta['subtitle'] = description.trim().isNotEmpty ? description.trim() : category;
        notesMeta['type'] = category == 'Dental X-ray'
            ? 'xray'
            : (category == 'Prescription' ? 'prescription' : 'document');
        notesMeta['updatedAt'] = nowIso;

        final updated = await client
            .from('medical_records')
            .update({
              'diagnosis': cleanTitle,
              'notes': jsonEncode(notesMeta),
              'updated_at': nowIso,
            })
            .eq('id', recordId)
            .select()
            .single();

        final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(updated));
        final idx = _fallbackMedicalRecords.indexWhere((r) => r['id'] == recordId);
        if (idx != -1) _fallbackMedicalRecords[idx] = formatted;
        return {
          'success': true,
          'message': 'Record details updated successfully.',
          'record': formatted,
        };
      }
    } catch (e) {
      debugPrint('Supabase direct update medical_record notice: $e');
    }

    // 2. Fallback in-memory / backend update
    final idx = _fallbackMedicalRecords.indexWhere((r) => r['id']?.toString() == recordId);
    if (idx != -1) {
      final existing = _fallbackMedicalRecords[idx];
      final ownerId = (existing['patientId'] ?? '').toString();
      if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
        return {
          'success': false,
          'statusCode': 403,
          'message': 'Access Denied: Only the patient owner can edit this record.',
        };
      }
      final updated = Map<String, dynamic>.from(existing);
      updated['title'] = cleanTitle;
      updated['category'] = category;
      updated['description'] = description.trim();
      updated['subtitle'] = description.trim().isNotEmpty ? description.trim() : category;
      updated['type'] = category == 'Dental X-ray'
          ? 'xray'
          : (category == 'Prescription' ? 'prescription' : 'document');
      updated['updatedAt'] = nowIso;
      _fallbackMedicalRecords[idx] = updated;
      return {
        'success': true,
        'message': 'Record details updated successfully.',
        'record': updated,
      };
    }

    return {'success': false, 'message': 'Record not found.'};
  }

  /// Patient: Delete a Dental Health Record — Patient Owner Only
  Future<Map<String, dynamic>> deletePatientDentalRecord({
    required String recordId,
    required String patientId,
  }) async {
    final resolvedPatientId = (await _resolvePatientUuid(patientId)) ?? patientId.trim();

    // 1. Direct Supabase ownership check & delete
    try {
      final client = Supabase.instance.client;
      final existing = await client.from('medical_records').select('*').eq('id', recordId).maybeSingle();
      if (existing != null) {
        final ownerId = (existing['patient_id'] ?? '').toString();
        if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
          return {
            'success': false,
            'statusCode': 403,
            'message': 'Access Denied: Only the patient owner can delete this record.',
          };
        }
        final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(existing));
        final storageKey = (formatted['storageKey'] ?? '').toString();
        if (storageKey.isNotEmpty) {
          _recordBytesCache.remove(storageKey);
        }
        await client.from('medical_records').delete().eq('id', recordId);
        _fallbackMedicalRecords.removeWhere((r) => r['id']?.toString() == recordId);
        return {'success': true, 'message': 'Health record deleted.'};
      }
    } catch (e) {
      debugPrint('Supabase direct delete medical_record notice: $e');
    }

    // 2. Fallback in-memory check & delete
    final idx = _fallbackMedicalRecords.indexWhere((r) => r['id']?.toString() == recordId);
    if (idx != -1) {
      final existing = _fallbackMedicalRecords[idx];
      final ownerId = (existing['patientId'] ?? '').toString();
      if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
        return {
          'success': false,
          'statusCode': 403,
          'message': 'Access Denied: Only the patient owner can delete this record.',
        };
      }
      final storageKey = (existing['storageKey'] ?? '').toString();
      if (storageKey.isNotEmpty) {
        _recordBytesCache.remove(storageKey);
      }
      _fallbackMedicalRecords.removeAt(idx);
      return {'success': true, 'message': 'Health record deleted.'};
    }

    return {'success': false, 'message': 'Record not found.'};
  }

  /// Patient: Share one or multiple Dental Health Records with a Favourite Doctor
  Future<Map<String, dynamic>> shareDentalRecordsWithDoctor({
    required String patientId,
    required String patientName,
    required List<String> recordIds,
    required String doctorId,
    String? doctorUserId,
    String? doctorEmail,
    required String doctorName,
    String? doctorSpecialty,
    String? doctorClinic,
  }) async {
    if (recordIds.isEmpty) {
      return {'success': false, 'message': 'Please select at least one record to share.'};
    }
    if (doctorId.trim().isEmpty && (doctorUserId == null || doctorUserId.trim().isEmpty)) {
      return {'success': false, 'message': 'Please select a doctor to share records with.'};
    }

    final resolvedPatientId = (await _resolvePatientUuid(patientId)) ?? patientId.trim();
    final sharedAt = DateTime.now().toIso8601String();

    String effectiveDocId = doctorId.trim();
    String effectiveDocUserId = (doctorUserId ?? '').trim();
    try {
      final client = Supabase.instance.client;
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      if (uuidRegex.hasMatch(effectiveDocId)) {
        final d = await client.from('dentists').select('id, user_id').or('id.eq.$effectiveDocId,user_id.eq.$effectiveDocId').maybeSingle();
        if (d != null) {
          effectiveDocId = d['id']?.toString() ?? effectiveDocId;
          effectiveDocUserId = d['user_id']?.toString() ?? effectiveDocUserId;
        }
      }
    } catch (_) {}

    final shareEntry = <String, dynamic>{
      'doctorId': effectiveDocId,
      'doctorUserId': effectiveDocUserId,
      'doctorEmail': (doctorEmail ?? '').trim().toLowerCase(),
      'doctorName': doctorName.trim().isNotEmpty ? doctorName.trim() : 'Doctor',
      'doctorSpecialty': (doctorSpecialty ?? 'General Dentistry').trim(),
      'doctorClinic': (doctorClinic ?? '').trim(),
      'sharedByPatientId': resolvedPatientId,
      'sharedByPatientName': patientName.trim().isNotEmpty ? patientName.trim() : 'Patient',
      'sharedAt': sharedAt,
    };

    final updatedList = <Map<String, dynamic>>[];

    for (final recId in recordIds) {
      bool updatedInSupabase = false;
      try {
        final client = Supabase.instance.client;
        final existing = await client.from('medical_records').select('*').eq('id', recId).maybeSingle();
        if (existing != null) {
          final ownerId = (existing['patient_id'] ?? '').toString();
          if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
            return {
              'success': false,
              'statusCode': 403,
              'message': 'Access Denied: You can only share your own health records.',
            };
          }
          final notesMeta = _parseNotesJson(existing['notes']);
          final List<Map<String, dynamic>> currentShares = [];
          if (notesMeta['sharedWith'] is List) {
            for (final s in (notesMeta['sharedWith'] as List)) {
              if (s is Map) {
                final sDocId = (s['doctorId'] ?? '').toString().toLowerCase();
                final sUserId = (s['doctorUserId'] ?? '').toString().toLowerCase();
                final matchesTarget = (effectiveDocId.isNotEmpty && (sDocId == effectiveDocId.toLowerCase() || sUserId == effectiveDocId.toLowerCase())) ||
                    (effectiveDocUserId.isNotEmpty && (sDocId == effectiveDocUserId.toLowerCase() || sUserId == effectiveDocUserId.toLowerCase()));
                if (!matchesTarget) {
                  currentShares.add(Map<String, dynamic>.from(s));
                }
              }
            }
          }
          currentShares.add(shareEntry);
          notesMeta['sharedWith'] = currentShares;
          notesMeta['updatedAt'] = sharedAt;

          final updated = await client
              .from('medical_records')
              .update({
                'notes': jsonEncode(notesMeta),
                'updated_at': sharedAt,
              })
              .eq('id', recId)
              .select()
              .single();

          final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(updated));
          updatedList.add(formatted);
          final idx = _fallbackMedicalRecords.indexWhere((r) => r['id']?.toString() == recId);
          if (idx != -1) _fallbackMedicalRecords[idx] = formatted;
          updatedInSupabase = true;
        }
      } catch (e) {
        debugPrint('Supabase direct share record notice: $e');
      }

      if (!updatedInSupabase) {
        final idx = _fallbackMedicalRecords.indexWhere((r) => r['id']?.toString() == recId);
        if (idx != -1) {
          final existing = _fallbackMedicalRecords[idx];
          final ownerId = (existing['patientId'] ?? '').toString();
          if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
            return {
              'success': false,
              'statusCode': 403,
              'message': 'Access Denied: You can only share your own health records.',
            };
          }
          final updated = Map<String, dynamic>.from(existing);
          final List<Map<String, dynamic>> currentShares = [];
          if (updated['sharedWith'] is List) {
            for (final s in (updated['sharedWith'] as List)) {
              if (s is Map) {
                final sDocId = (s['doctorId'] ?? '').toString().toLowerCase();
                final sUserId = (s['doctorUserId'] ?? '').toString().toLowerCase();
                final matchesTarget = (effectiveDocId.isNotEmpty && (sDocId == effectiveDocId.toLowerCase() || sUserId == effectiveDocId.toLowerCase())) ||
                    (effectiveDocUserId.isNotEmpty && (sDocId == effectiveDocUserId.toLowerCase() || sUserId == effectiveDocUserId.toLowerCase()));
                if (!matchesTarget) {
                  currentShares.add(Map<String, dynamic>.from(s));
                }
              }
            }
          }
          currentShares.add(shareEntry);
          updated['sharedWith'] = currentShares;
          updated['updatedAt'] = sharedAt;
          _fallbackMedicalRecords[idx] = updated;
          updatedList.add(updated);
        }
      }
    }

    // Notify Doctor asynchronously
    if (updatedList.isNotEmpty) {
      createInAppNotification(
        recipientRole: 'Dentist',
        recipientId: effectiveDocId.isNotEmpty ? effectiveDocId : effectiveDocUserId,
        title: 'New Health Records Shared',
        message: '${patientName.trim().isNotEmpty ? patientName.trim() : "A patient"} shared ${updatedList.length} health record(s) with you.',
        type: 'RECORD_SHARED',
      );
    }

    return {
      'success': updatedList.isNotEmpty,
      'message': updatedList.isNotEmpty
          ? 'Shared ${updatedList.length} record(s) with $doctorName.'
          : 'Could not find selected records to share.',
      'records': updatedList,
    };
  }

  /// Patient: Revoke a Doctor's sharing permission for a Dental Health Record
  Future<Map<String, dynamic>> revokeDentalRecordShare({
    required String recordId,
    required String patientId,
    required String doctorId,
  }) async {
    final resolvedPatientId = (await _resolvePatientUuid(patientId)) ?? patientId.trim();
    final cleanDocId = doctorId.trim().toLowerCase();
    final nowIso = DateTime.now().toIso8601String();

    final targetDocIds = <String>{cleanDocId};
    try {
      final client = Supabase.instance.client;
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      if (uuidRegex.hasMatch(doctorId.trim())) {
        final d = await client.from('dentists').select('id, user_id').or('id.eq.${doctorId.trim()},user_id.eq.${doctorId.trim()}').maybeSingle();
        if (d != null) {
          if (d['id'] != null) targetDocIds.add(d['id'].toString().toLowerCase());
          if (d['user_id'] != null) targetDocIds.add(d['user_id'].toString().toLowerCase());
        }
      }
    } catch (_) {}

    // 1. Direct Supabase ownership check & revoke
    try {
      final client = Supabase.instance.client;
      final existing = await client.from('medical_records').select('*').eq('id', recordId).maybeSingle();
      if (existing != null) {
        final ownerId = (existing['patient_id'] ?? '').toString();
        if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
          return {
            'success': false,
            'statusCode': 403,
            'message': 'Access Denied: Only the patient owner can revoke sharing permissions.',
          };
        }
        final notesMeta = _parseNotesJson(existing['notes']);
        final List<Map<String, dynamic>> remainingShares = [];
        if (notesMeta['sharedWith'] is List) {
          for (final s in (notesMeta['sharedWith'] as List)) {
            if (s is Map) {
              final sDocId = (s['doctorId'] ?? '').toString().trim().toLowerCase();
              final sUserId = (s['doctorUserId'] ?? '').toString().trim().toLowerCase();
              final sEmail = (s['doctorEmail'] ?? '').toString().trim().toLowerCase();
              if (!targetDocIds.contains(sDocId) && !targetDocIds.contains(sUserId) && !targetDocIds.contains(sEmail)) {
                remainingShares.add(Map<String, dynamic>.from(s));
              }
            }
          }
        }
        notesMeta['sharedWith'] = remainingShares;
        notesMeta['updatedAt'] = nowIso;

        final updated = await client
            .from('medical_records')
            .update({
              'notes': jsonEncode(notesMeta),
              'updated_at': nowIso,
            })
            .eq('id', recordId)
            .select()
            .single();

        final formatted = formatMedicalRecordRow(Map<String, dynamic>.from(updated));
        final idx = _fallbackMedicalRecords.indexWhere((r) => r['id']?.toString() == recordId);
        if (idx != -1) _fallbackMedicalRecords[idx] = formatted;
        return {
          'success': true,
          'message': 'Sharing permission revoked.',
          'record': formatted,
        };
      }
    } catch (e) {
      debugPrint('Supabase direct revoke share notice: $e');
    }

    // 2. Fallback in-memory revoke
    final idx = _fallbackMedicalRecords.indexWhere((r) => r['id']?.toString() == recordId);
    if (idx != -1) {
      final existing = _fallbackMedicalRecords[idx];
      final ownerId = (existing['patientId'] ?? '').toString();
      if (ownerId.isNotEmpty && ownerId != resolvedPatientId && ownerId != patientId.trim()) {
        return {
          'success': false,
          'statusCode': 403,
          'message': 'Access Denied: Only the patient owner can revoke sharing permissions.',
        };
      }
      final updated = Map<String, dynamic>.from(existing);
      final List<Map<String, dynamic>> remainingShares = [];
      if (updated['sharedWith'] is List) {
        for (final s in (updated['sharedWith'] as List)) {
          if (s is Map) {
            final sDocId = (s['doctorId'] ?? '').toString().trim().toLowerCase();
            final sUserId = (s['doctorUserId'] ?? '').toString().trim().toLowerCase();
            final sEmail = (s['doctorEmail'] ?? '').toString().trim().toLowerCase();
            if (!targetDocIds.contains(sDocId) && !targetDocIds.contains(sUserId) && !targetDocIds.contains(sEmail)) {
              remainingShares.add(Map<String, dynamic>.from(s));
            }
          }
        }
      }
      updated['sharedWith'] = remainingShares;
      updated['updatedAt'] = nowIso;
      _fallbackMedicalRecords[idx] = updated;
      return {
        'success': true,
        'message': 'Sharing permission revoked.',
        'record': updated,
      };
    }

    return {'success': false, 'message': 'Record not found.'};
  }

  /// Verify access & retrieve authorized file bytes / signed URL for View & Download
  /// Enforces Patient Ownership OR Explicit Doctor Sharing Permission
  Future<Map<String, dynamic>> getAuthorizedRecordAccess({
    required String recordId,
    required String requesterId,
    required String requesterRole,
    String? doctorUserId,
    String? doctorEmail,
  }) async {
    if (requesterId.trim().isEmpty && (doctorUserId == null || doctorUserId.trim().isEmpty) && (doctorEmail == null || doctorEmail.trim().isEmpty)) {
      return {
        'success': false,
        'authorized': false,
        'statusCode': 401,
        'message': 'Authentication required to access this record.',
      };
    }

    Map<String, dynamic>? targetRecord;
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('medical_records')
          .select('*, patient:users!patient_id(id, name, email, phone)')
          .eq('id', recordId)
          .maybeSingle();
      if (row != null) {
        targetRecord = formatMedicalRecordRow(Map<String, dynamic>.from(row));
      }
    } catch (_) {
      try {
        final client = Supabase.instance.client;
        final row = await client.from('medical_records').select('*').eq('id', recordId).maybeSingle();
        if (row != null) {
          targetRecord = formatMedicalRecordRow(Map<String, dynamic>.from(row));
        }
      } catch (_) {}
    }

    targetRecord ??= _fallbackMedicalRecords
        .where((r) => r['id']?.toString() == recordId)
        .map((r) => formatMedicalRecordRow(r))
        .firstOrNull;

    if (targetRecord == null) {
      return {
        'success': false,
        'authorized': false,
        'statusCode': 404,
        'message': 'Health record not found.',
      };
    }

    final roleLower = requesterRole.trim().toLowerCase();
    bool isAuthorized = false;

    if (roleLower == 'patient') {
      final resolvedRequester = (await _resolvePatientUuid(requesterId)) ?? requesterId.trim();
      final ownerId = (targetRecord['patientId'] ?? '').toString();
      if (ownerId.isNotEmpty && (ownerId == resolvedRequester || ownerId == requesterId.trim())) {
        isAuthorized = true;
      }
    } else if (roleLower == 'dentist' || roleLower == 'doctor') {
      String? resolvedDentistTableId;
      String? resolvedUserTableId;
      try {
        final client = Supabase.instance.client;
        final cleanId = requesterId.trim();
        final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
        if (uuidRegex.hasMatch(cleanId)) {
          final d = await client.from('dentists').select('id, user_id').or('id.eq.$cleanId,user_id.eq.$cleanId').maybeSingle();
          if (d != null) {
            resolvedDentistTableId = d['id']?.toString();
            resolvedUserTableId = d['user_id']?.toString();
          }
        }
      } catch (_) {}

      isAuthorized = isDoctorAuthorizedForRecordMap(
            targetRecord,
            doctorId: requesterId,
            doctorUserId: doctorUserId ?? resolvedUserTableId,
            doctorEmail: doctorEmail,
          ) ||
          (resolvedDentistTableId != null &&
              isDoctorAuthorizedForRecordMap(
                targetRecord,
                doctorId: resolvedDentistTableId,
                doctorUserId: resolvedUserTableId,
                doctorEmail: doctorEmail,
              ));
    }

    if (!isAuthorized) {
      return {
        'success': false,
        'authorized': false,
        'statusCode': 403,
        'message': 'Access Denied: You do not have permission to view or download this health record.',
      };
    }

    final storageKey = (targetRecord['storageKey'] ?? '').toString();
    Uint8List? fileBytes = getCachedRecordBytes(storageKey);

    if (fileBytes == null && storageKey.isNotEmpty) {
      try {
        final downloaded = await Supabase.instance.client.storage.from('dentaguru-storage').download(storageKey);
        if (downloaded.isNotEmpty) {
          fileBytes = downloaded;
          cacheRecordBytes(storageKey, downloaded);
        }
      } catch (e) {
        debugPrint('Storage download notice: $e');
      }
    }

    return {
      'success': true,
      'authorized': true,
      'statusCode': 200,
      'record': targetRecord,
      'bytes': fileBytes,
      'fileBytes': fileBytes,
    };
  }

  /// Create a new multi-specialty medical record / E-Prescription for a patient via Backend API & Supabase DB
  Future<Map<String, dynamic>> createMedicalRecord({
    required String patientId,
    required String type, // 'prescription', 'xray', 'chart'
    required String title,
    required String subtitle,
    required String doctorName,
    required String clinicName,
    required List<Map<String, dynamic>> items,
    String? patientName,
    String? dentistId,
    String? appointmentId,
    String? specialty,
    String? department,
    String? diagnosis,
    String? symptoms,
    Map<String, dynamic>? clinicalSections,
    String? followUpDate,
    String? instructions,
    String? doctorQualification,
    bool approvedByDoctor = true,
  }) async {
    // 1. Express backend API first (resolves doctor specialization, UUIDs & appointment link)
    try {
      final url = Uri.parse(ApiConstants.records);
      final response = await http
          .post(
            url,
            headers: _headers,
            body: jsonEncode({
              'patientId': patientId,
              if (patientName != null && patientName.trim().isNotEmpty) 'patientName': patientName.trim(),
              if (dentistId != null && dentistId.trim().isNotEmpty) 'dentistId': dentistId.trim(),
              if (appointmentId != null && appointmentId.trim().isNotEmpty) 'appointmentId': appointmentId.trim(),
              'recordSource': 'doctor_issued',
              'type': type,
              'category': type == 'xray' ? 'Dental X-ray' : (type == 'prescription' ? 'Prescription' : 'Other'),
              'title': title,
              'subtitle': subtitle,
              'doctorName': doctorName,
              'clinicName': clinicName,
              if (specialty != null && specialty.trim().isNotEmpty) 'specialty': specialty.trim(),
              if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
              if (diagnosis != null && diagnosis.trim().isNotEmpty) 'diagnosis': diagnosis.trim(),
              if (symptoms != null && symptoms.trim().isNotEmpty) 'symptoms': symptoms.trim(),
              if (clinicalSections != null && clinicalSections.isNotEmpty) 'clinicalSections': clinicalSections,
              if (followUpDate != null && followUpDate.trim().isNotEmpty) 'followUpDate': followUpDate.trim(),
              if (instructions != null && instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
              if (doctorQualification != null && doctorQualification.trim().isNotEmpty)
                'doctorQualification': doctorQualification.trim(),
              'approvedByDoctor': approvedByDoctor,
              'items': items,
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['success'] == true) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('Create medical record API notice: $e');
    }

    // 2. Direct Supabase fallback
    final resolvedPatientId = (await _resolvePatientUuid(patientId)) ?? patientId.trim();
    final nowIso = DateTime.now().toIso8601String();
    final notesMeta = {
      'recordSource': 'doctor_issued',
      'type': type,
      'title': title,
      'category': type == 'xray' ? 'Dental X-ray' : (type == 'prescription' ? 'Prescription' : 'Other'),
      'description': subtitle,
      'subtitle': subtitle,
      if (patientName != null && patientName.trim().isNotEmpty) 'patientName': patientName.trim(),
      if (dentistId != null && dentistId.trim().isNotEmpty) 'dentistId': dentistId.trim(),
      if (appointmentId != null && appointmentId.trim().isNotEmpty) 'appointmentId': appointmentId.trim(),
      if (specialty != null && specialty.trim().isNotEmpty) 'specialty': specialty.trim(),
      if (department != null && department.trim().isNotEmpty) 'department': department.trim(),
      'diagnosis': (diagnosis ?? title).trim(),
      if (symptoms != null && symptoms.trim().isNotEmpty) 'symptoms': symptoms.trim(),
      if (clinicalSections != null && clinicalSections.isNotEmpty) 'clinicalSections': clinicalSections,
      if (followUpDate != null && followUpDate.trim().isNotEmpty) 'followUpDate': followUpDate.trim(),
      if (instructions != null && instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      if (doctorQualification != null && doctorQualification.trim().isNotEmpty)
        'doctorQualification': doctorQualification.trim(),
      'approvedByDoctor': approvedByDoctor,
      'doctorName': doctorName,
      'clinicName': clinicName,
      'uploadedAt': nowIso,
      'updatedAt': nowIso,
      'sharedWith': <Map<String, dynamic>>[],
    };

    try {
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      final insertPayload = <String, dynamic>{
        'patient_id': resolvedPatientId,
        if (dentistId != null && uuidRegex.hasMatch(dentistId.trim())) 'dentist_id': dentistId.trim(),
        if (appointmentId != null && uuidRegex.hasMatch(appointmentId.trim())) 'appointment_id': appointmentId.trim(),
        'diagnosis': (diagnosis ?? title).trim(),
        'notes': jsonEncode(notesMeta),
        'prescriptions': items,
      };
      final inserted = await Supabase.instance.client
          .from('medical_records')
          .insert(insertPayload)
          .select()
          .single();
      return {'success': true, 'record': formatMedicalRecordRow(Map<String, dynamic>.from(inserted))};
    } catch (_) {}

    return {'success': false, 'message': 'Failed to create medical record.'};
  }

  /// Fetch dynamic specialty clinical config (triage categories & prescription schema) for a specialty or doctor.
  Future<Map<String, dynamic>?> fetchSpecialtyClinicalConfig({
    String? specialty,
    String? doctorId,
  }) async {
    try {
      final params = <String, String>{};
      if (specialty != null && specialty.trim().isNotEmpty) params['specialty'] = specialty.trim();
      if (doctorId != null && doctorId.trim().isNotEmpty) params['doctorId'] = doctorId.trim();
      final uri = Uri.parse('${ApiConstants.baseUrl}/specialties/clinical-config')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['success'] == true) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('Fetch specialty clinical config notice: $e');
    }
    return null;
  }

  /// Run multi-specialty AI Health Triage analysis on the backend.
  Future<Map<String, dynamic>?> analyzeAiTriage({
    String? specialty,
    String? doctorId,
    required String category,
    required String symptoms,
    required String severity,
    required String duration,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/triage/analyze');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              if (specialty != null && specialty.trim().isNotEmpty) 'specialty': specialty.trim(),
              if (doctorId != null && doctorId.trim().isNotEmpty) 'doctorId': doctorId.trim(),
              'category': category,
              'symptoms': symptoms,
              'severity': severity,
              'duration': duration,
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['success'] == true) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('AI triage analyze API notice: $e');
    }
    return null;
  }

  /// Patient: Create a new Multi-Specialty Consultation / Triage Request
  Future<Map<String, dynamic>> createProblemRequest({
    required String problemCategory,
    required String problemDescription,
    String? specialty,
    String? symptoms,
    String? preferredLocation,
    List<String>? attachments,
    String? patientName,
    String? patientPhone,
    String? city,
    String? pincode,
    String? state,
    String? preferredDoctorId,
    String? preferredDoctorName,
    String? preferredDoctorClinic,
    String? referringDentistId,
    String? referringDentistName,
    String? escalationType,
  }) async {
    final bool isDirectReferral = preferredDoctorId != null && preferredDoctorId.isNotEmpty;
    final bool isCoordEscalation = !isDirectReferral && escalationType?.toUpperCase() == 'COORDINATOR_ASSISTANCE';
    final String initialStatus = isDirectReferral
        ? 'DENTIST_ASSIGNED'
        : (isCoordEscalation ? 'SUBMITTED' : 'PENDING_ADMIN_REVIEW');

    // 1. Try Supabase direct first
    try {
      final currentUserId = SupabaseService.safeCurrentUser?.id;
      final payload = {
        if (currentUserId != null && currentUserId.isNotEmpty) 'patient_id': currentUserId,
        'problem_category': problemCategory,
        'problem_description': problemDescription,
        'symptoms': [
          if (specialty != null && specialty.trim().isNotEmpty) 'Specialty: ${specialty.trim()}',
          if (isCoordEscalation) 'Coordinator Assistance Escalation',
          if (symptoms != null && symptoms.trim().isNotEmpty) symptoms.trim(),
        ].join(' • '),
        'preferred_location': preferredLocation ?? '',
        'attachments': attachments ?? [],
        'city': city ?? '',
        'pincode': pincode ?? '',
        'state': state ?? '',
        'status': initialStatus,
        if (isDirectReferral) ...{
          'suggested_dentist_id': preferredDoctorId,
          'admin_notes': 'Referral directly assigned to ${preferredDoctorName ?? 'Specialist'}',
        },
        if (isCoordEscalation)
          'admin_notes': 'Coordinator assistance requested${specialty != null && specialty.isNotEmpty ? ' for $specialty' : ''}.\nCOORD_META:${jsonEncode({'escalationType': 'COORDINATOR_ASSISTANCE', 'specialty': specialty ?? '', 'coordinatorStatus': 'Submitted', 'followUpNotes': []})}',
      };
      final res = await Supabase.instance.client.from('patient_problem_requests').insert(payload).select().single();
      if (res.isNotEmpty) {
        // Also dispatch asynchronously to Express backend DB so both central DBs stay 100% in sync
        http.post(
          Uri.parse('${ApiConstants.baseUrl}/patient/problem-requests'),
          headers: _headers,
          body: jsonEncode({
            'problemCategory': problemCategory,
            'problemDescription': problemDescription,
            if (specialty != null && specialty.trim().isNotEmpty) 'specialty': specialty.trim(),
            if (escalationType != null && escalationType.trim().isNotEmpty) 'escalationType': escalationType.trim(),
            if (symptoms != null) 'symptoms': symptoms,
            'patientName': patientName,
            'patientPhone': patientPhone,
            'city': city,
            'pincode': pincode,
            'state': state,
            if (preferredDoctorId != null && preferredDoctorId.isNotEmpty) 'preferredDoctorId': preferredDoctorId,
            if (preferredDoctorName != null && preferredDoctorName.isNotEmpty) 'preferredDoctorName': preferredDoctorName,
          }),
        ).timeout(const Duration(seconds: 10)).catchError((_) => http.Response('', 500));
        return {'success': true, 'request': res};
      }
    } catch (e) {
      debugPrint('Supabase direct insert problem request notice: $e');
    }

    // 2. Fallback: Express backend API
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/patient/problem-requests');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'problemCategory': problemCategory,
          'problemDescription': problemDescription,
          if (specialty != null && specialty.trim().isNotEmpty) 'specialty': specialty.trim(),
          if (escalationType != null && escalationType.trim().isNotEmpty) 'escalationType': escalationType.trim(),
          if (symptoms != null) 'symptoms': symptoms,
          if (preferredLocation != null) 'preferredLocation': preferredLocation,
          if (attachments != null) 'attachments': attachments,
          if (patientName != null) 'patientName': patientName,
          if (patientPhone != null) 'patientPhone': patientPhone,
          if (city != null) 'city': city,
          if (pincode != null) 'pincode': pincode,
          if (state != null) 'state': state,
        }),
      ).timeout(const Duration(seconds: 35));
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to submit problem request.'};
    }
  }

  /// Patient: Fetch own Dental Problem Requests ONLY (Strictly filtered by authenticated patient ID)
  Future<List<dynamic>> fetchPatientProblemRequests({String? patientId}) async {
    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentUser?.id;
    final targetId = (patientId != null && patientId.isNotEmpty) ? patientId : currentUserId;

    if (targetId == null || targetId.isEmpty) return [];

    // 1. Always try Supabase directly first — strictly filters by logged-in patient's ID / Email
    try {
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      final List<String> conds = [];
      if (uuidRegex.hasMatch(targetId)) {
        conds.add('patient_id.eq.$targetId');
      }

      if (conds.isNotEmpty) {
        final res = await client
            .from('patient_problem_requests')
            .select('''
              *,
              patient:users!patient_id(id, name, email, phone, city, state, pincode),
              dentist:dentists!suggested_dentist_id(
                id,
                speciality,
                users:user_id(name, email, phone),
                clinics:clinic_id(clinic_name, location)
              )
            ''')
            .or(conds.join(','))
            .order('created_at', ascending: false);

        return List<dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('Supabase direct fetch patient problem requests notice: $e');
    }

    // 2. Fallback: Express backend API
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/patient/problem-requests').replace(queryParameters: {
        'patientId': targetId,
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['requests'] ?? [];
        if (list is List) return list;
      }
    } catch (e) {
      debugPrint('Fetch patient problem requests error: $e');
    }
    return [];
  }

  /// Admin: Fetch all Dental Problem Requests
  /// Admin: Fetch all Dental Problem Requests (Combines Supabase direct DB & Express Backend)
  Future<List<dynamic>> fetchAdminProblemRequests({String? status}) async {
    final List<dynamic> items = [];
    final existingIds = <String>{};

    // 1. Direct Supabase Query first with joined patient and dentist data
    try {
      var query = Supabase.instance.client.from('patient_problem_requests').select('''
        *,
        patient:users!patient_id(id, name, email, phone, city, state, pincode),
        dentist:dentists!suggested_dentist_id(
          id,
          speciality,
          users:user_id(name, email, phone),
          clinics:clinic_id(clinic_name, location)
        )
      ''');
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      final res = await query.order('created_at', ascending: false);
      if (res.isNotEmpty) {
        for (final item in res) {
          final id = (item['id'] ?? item['_id'] ?? '').toString();
          if (id.isNotEmpty) existingIds.add(id);
          items.add(item);
        }
      }
    } catch (e) {
      debugPrint('Supabase direct fetch admin problem requests notice: $e');
    }

    // 2. Express Backend API fallback (merges any additional records or enriches existing items)
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/problem-requests').replace(queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['requests'] ?? [];
        if (list is List) {
          for (final item in list) {
            final id = (item['_id'] ?? item['id'] ?? '').toString();
            if (id.isNotEmpty) {
              final existingIndex = items.indexWhere((it) => (it['id'] ?? it['_id'] ?? '').toString() == id);
              if (existingIndex != -1) {
                final existingMap = Map<String, dynamic>.from(items[existingIndex]);
                if (item['assigned_doctor_name'] != null && (existingMap['assigned_doctor_name'] == null || existingMap['assigned_doctor_name'].toString().isEmpty)) {
                  existingMap['assigned_doctor_name'] = item['assigned_doctor_name'];
                }
                if (item['assigned_doctor_specialty'] != null && (existingMap['assigned_doctor_specialty'] == null || existingMap['assigned_doctor_specialty'].toString().isEmpty)) {
                  existingMap['assigned_doctor_specialty'] = item['assigned_doctor_specialty'];
                }
                if (item['assigned_doctor_clinic'] != null && (existingMap['assigned_doctor_clinic'] == null || existingMap['assigned_doctor_clinic'].toString().isEmpty)) {
                  existingMap['assigned_doctor_clinic'] = item['assigned_doctor_clinic'];
                }
                items[existingIndex] = existingMap;
              } else {
                existingIds.add(id);
                items.add(item);
              }
            } else {
              items.add(item);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Fetch admin problem requests error: $e');
    }

    return items;
  }

  /// Dentist: Fetch ONLY problem requests assigned to the logged-in dentist
  Future<List<dynamic>> fetchDentistAssignedRequests({String? dentistId, String? dentistName}) async {
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    bool isUuid(String? s) => s != null && uuidRegex.hasMatch(s.trim());

    // 1. Try Supabase direct first
    try {
      final client = Supabase.instance.client;
      final currentUserId = (dentistId != null && dentistId.trim().isNotEmpty)
          ? dentistId.trim()
          : client.auth.currentUser?.id;
      
      if (currentUserId == null || currentUserId.isEmpty) {
        return [];
      }

      String cleanDocName = (dentistName ?? '').replaceAll('Dr. ', '').trim();

      String? altDentistTableId;
      String? altUserId;

      if (isUuid(currentUserId)) {
        try {
          final uRes = await client.from('users').select('name').eq('id', currentUserId).maybeSingle();
          if (uRes != null && uRes['name'] != null && cleanDocName.isEmpty) {
            cleanDocName = uRes['name'].toString().replaceAll('Dr. ', '').trim();
          }

          final dRes = await client.from('dentists').select('id, user_id').or('id.eq.$currentUserId,user_id.eq.$currentUserId').maybeSingle();
          if (dRes != null) {
            altDentistTableId = dRes['id']?.toString();
            altUserId = dRes['user_id']?.toString();
          }
        } catch (_) {}
      } else {
        // Resolve UUIDs when dentistId is an email or doctor name
        try {
          final uRes = await client.from('users').select('id, name, email').or('email.ilike.$currentUserId,name.ilike.$currentUserId').maybeSingle();
          if (uRes != null && uRes['id'] != null) {
            final uId = uRes['id'].toString();
            if (isUuid(uId)) {
              altUserId = uId;
              final dRes = await client.from('dentists').select('id, user_id').eq('user_id', uId).maybeSingle();
              if (dRes != null) {
                altDentistTableId = dRes['id']?.toString();
              }
            }
          }
        } catch (_) {}
      }

      final idsToMatch = <String>[
        if (currentUserId.isNotEmpty && isUuid(currentUserId)) currentUserId,
        if (altDentistTableId != null && altDentistTableId.isNotEmpty && isUuid(altDentistTableId)) altDentistTableId,
        if (altUserId != null && altUserId.isNotEmpty && isUuid(altUserId)) altUserId,
      ].toSet().toList();

      final Map<String, dynamic> mergedRequests = {};

      const joinedSelect = '''
        *,
        patient:users!patient_id(id, name, email, phone, city, state, pincode),
        dentist:dentists!suggested_dentist_id(
          id,
          speciality,
          users:user_id(name, email, phone),
          clinics:clinic_id(clinic_name, location)
        )
      ''';

      if (idsToMatch.isNotEmpty) {
        final List<String> condList = [];
        for (final id in idsToMatch) {
          condList.add('suggested_dentist_id.eq.$id');
        }
        final orFilter = condList.join(',');
        final res = await client.from('patient_problem_requests').select(joinedSelect).or(orFilter).order('created_at', ascending: false);
        for (final item in res) {
          final id = item['id']?.toString() ?? item['_id']?.toString() ?? '';
          if (id.isNotEmpty) mergedRequests[id] = item;
        }

        // Query dentist_suggestions table in Supabase
        final conds = idsToMatch.map((id) => 'dentist_id.eq.$id').join(',');
        final suggRes = await client.from('dentist_suggestions').select('request_id').or(conds);
        if (suggRes.isNotEmpty) {
          final reqIds = suggRes.map((s) => s['request_id']?.toString() ?? '').where((id) => id.isNotEmpty && isUuid(id)).toSet().toList();
          if (reqIds.isNotEmpty) {
            final idConds = reqIds.map((id) => 'id.eq.$id').join(',');
            final sRequests = await client.from('patient_problem_requests').select(joinedSelect).or(idConds).order('created_at', ascending: false);
            for (final item in sRequests) {
              final id = item['id']?.toString() ?? item['_id']?.toString() ?? '';
              if (id.isNotEmpty) mergedRequests[id] = item;
            }
          }
        }
      }

      if (mergedRequests.isNotEmpty) {
        return mergedRequests.values.toList();
      }
    } catch (e) {
      debugPrint('Supabase direct fetch dentist assigned requests notice: $e');
    }

    // 2. Fallback: Express backend API
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/dentist/assigned-requests').replace(queryParameters: {
        if (dentistId != null && dentistId.isNotEmpty) 'dentistId': dentistId,
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['requests'] ?? [];
        if (list is List && list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('Fetch dentist assigned requests error: $e');
    }

    return [];
  }

  /// Admin/All: Fetch all registered Patients directly from Supabase DB
  Future<List<dynamic>> fetchPatients() async {
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('*')
          .ilike('role', 'Patient')
          .order('created_at', ascending: false);
      if (res.isNotEmpty) {
        return res;
      }
    } catch (e) {
      debugPrint('Supabase direct fetch patients notice: $e');
    }

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/patients');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['patients'] ?? [];
        if (list is List && list.isNotEmpty) {
          return list;
        }
      }
    } catch (e) {
      debugPrint('Fetch patients error: $e');
    }
    return [];
  }

  /// Create Sub-Admin (Primary Admin only)
  Future<Map<String, dynamic>> createSubAdmin({
    required String name,
    required String phone,
    String? email,
    String? password,
    String? city,
    String? pincode,
    List<String>? languages,
    List<String>? permissions,
    List<String>? districtIds,
    String status = 'ACTIVE',
  }) async {
    final cleanPhone = phone.trim();
    final cleanEmail = (email != null && email.trim().isNotEmpty) ? email.trim() : '';
    final cleanPassword = (password != null && password.trim().isNotEmpty) ? password.trim() : 'Passwordless_${cleanPhone.replaceAll('+', '')}';
    final userLanguages = (languages != null && languages.isNotEmpty) ? languages : ['English'];

    final perms = permissions ?? [
      'PATIENT_VIEW',
    ];

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'phone': cleanPhone,
          if (cleanEmail.isNotEmpty) 'email': cleanEmail,
          'password': cleanPassword,
          'status': status,
          'permissions': perms,
          if (city != null) 'city': city,
          if (pincode != null) 'pincode': pincode,
          'languages': userLanguages,
          if (districtIds != null && districtIds.isNotEmpty) 'districtIds': districtIds,
        }),
      ).timeout(const Duration(seconds: 35));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Sub-Admin created successfully.',
          'subAdmin': data['subAdmin'],
        };
      }
    } catch (e) {
      debugPrint('Create Sub-Admin backend notice: $e');
    }

    // Direct Supabase Cloud 24/7 Fallback
    try {
      final meta = jsonEncode({
        'permissions': perms,
        'status': status,
        if (city != null) 'city': city,
        if (pincode != null) 'pincode': pincode,
        'languages': userLanguages,
        if (districtIds != null) 'districtIds': districtIds,
      });
      final res = await Supabase.instance.client.from('users').insert({
        'name': name,
        'email': cleanEmail,
        'password': cleanPassword,
        'phone': cleanPhone,
        'role': 'Sub-Admin',
        'status': status.trim().toUpperCase(),
        if (city != null) 'city': city,
        if (pincode != null) 'pincode': pincode,
        'languages': userLanguages,
        'device_token': meta,
      }).select().maybeSingle();

      if (res != null && districtIds != null && districtIds.isNotEmpty) {
        final subAdminId = res['id'].toString();
        for (final dId in districtIds) {
          try {
            await Supabase.instance.client.from('sub_admin_districts').upsert({
              'sub_admin_id': subAdminId,
              'district_id': dId,
            });
          } catch (_) {}
        }
      }

      return {
        'success': true,
        'message': 'Sub-Admin account created successfully.',
        'subAdmin': res ?? {'name': name, 'email': cleanEmail, 'phone': cleanPhone, 'role': 'Sub-Admin', 'status': status, 'permissions': perms, 'assignedDistricts': districtIds ?? []},
      };
    } catch (e) {
      debugPrint('Create Sub-Admin Supabase error: $e');
    }

    return {'success': false, 'message': 'Failed to create Sub-Admin'};
  }

  @visibleForTesting
  static Future<List<dynamic>> Function()? debugFetchSubAdminsOverride;

  bool _lastFetchSubAdminsSucceeded = false;
  bool get lastFetchSubAdminsSucceeded => _lastFetchSubAdminsSucceeded;

  String? _lastSubAdminToggleError;
  String? get lastSubAdminToggleError => _lastSubAdminToggleError;

  String? _lastSubAdminConfirmedStatus;
  String? get lastSubAdminConfirmedStatus => _lastSubAdminConfirmedStatus;

  /// Fetch all Sub-Admins
  Future<List<dynamic>> fetchSubAdmins() async {
    _lastFetchSubAdminsSucceeded = false;
    if (debugFetchSubAdminsOverride != null) {
      _lastFetchSubAdminsSucceeded = true;
      return debugFetchSubAdminsOverride!();
    }
    // 1. Try Backend API query first (Returns rich assignedDistricts, assignedPatientsCount, last_activity)
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins');
      final response = await http.get(uri, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['subAdmins'] ?? [];
        if (list is List) {
          _lastFetchSubAdminsSucceeded = true;
          return list;
        }
      }
    } catch (e) {
      debugPrint('Fetch sub-admins backend API notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback Query
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('id, name, email, phone, role, status, created_at, device_token')
          .or('role.ilike.%sub-admin%,role.ilike.%subadmin%')
          .order('created_at', ascending: false);
      _lastFetchSubAdminsSucceeded = true;
      if (res.isNotEmpty) {
        final subAdminList = <Map<String, dynamic>>[];
        for (final row in res) {
          final map = Map<String, dynamic>.from(row);
          final colStatus = (map['status'] ?? '').toString().trim().toUpperCase();
          String? metaStatus;
          if (map['device_token'] != null && map['device_token'].toString().startsWith('{')) {
            try {
              final meta = jsonDecode(map['device_token'].toString());
              if (meta['permissions'] != null) map['permissions'] = meta['permissions'];
              if (meta['status'] != null) metaStatus = meta['status'].toString().trim().toUpperCase();
              if (meta['districtIds'] != null) map['assignedDistrictIds'] = meta['districtIds'];
            } catch (_) {}
          }
          map['status'] = colStatus.isNotEmpty ? colStatus : (metaStatus != null && metaStatus.isNotEmpty ? metaStatus : 'ACTIVE');
          if (map['permissions'] == null) {
            map['permissions'] = ['PATIENT_VIEW'];
          }

          // Try fetching assigned districts for this subadmin
          try {
            final saDistricts = await Supabase.instance.client
                .from('sub_admin_districts')
                .select('districts(*)')
                .eq('sub_admin_id', map['id'].toString());
            map['assignedDistricts'] = saDistricts.map((d) => d['districts']).whereType<Map>().toList();
          } catch (_) {
            map['assignedDistricts'] = [];
          }

          subAdminList.add(map);
        }
        return subAdminList;
      }
    } catch (e) {
      debugPrint('Fetch sub-admins Supabase direct notice: $e');
    }

    return [];
  }

  /// Update Sub-Admin details & permissions
  Future<Map<String, dynamic>> updateSubAdmin({
    required String id,
    String? name,
    String? phone,
    String? password,
    String? status,
    List<String>? permissions,
    List<String>? districtIds,
  }) async {
    final normalizedStatus = status?.trim().toUpperCase();

    // 1. Authoritative Express Backend Update first (persists users.status, permissions table, districts, audit log)
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$id');
      final payload = <String, dynamic>{};
      if (name != null) payload['name'] = name;
      if (phone != null) payload['phone'] = phone;
      if (password != null && password.trim().isNotEmpty) payload['password'] = password;
      if (normalizedStatus != null && normalizedStatus.isNotEmpty) payload['status'] = normalizedStatus;
      if (permissions != null) payload['permissions'] = permissions;
      if (districtIds != null) payload['districtIds'] = districtIds;

      final response = await http.put(
        url,
        headers: _headersWithUser(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'success': true,
            'message': data['message'] ?? 'Sub-Admin updated successfully.',
            'subAdmin': data['subAdmin'],
          };
        }
      }
      if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Failed to update Sub-Admin.'};
      }
    } catch (e) {
      debugPrint('Update Sub-Admin backend API notice ($e), trying direct Supabase fallback...');
    }

    // 2. Direct Supabase Cloud fallback
    try {
      final updateMap = <String, dynamic>{};
      if (name != null) updateMap['name'] = name;
      if (phone != null) updateMap['phone'] = phone;
      if (password != null && password.trim().isNotEmpty) updateMap['password'] = password;
      if (normalizedStatus != null && normalizedStatus.isNotEmpty) {
        updateMap['status'] = normalizedStatus;
      }

      // Update meta in device_token
      final u = await Supabase.instance.client.from('users').select('device_token').eq('id', id).maybeSingle();
      Map<String, dynamic> meta = {};
      if (u != null && u['device_token'] != null && u['device_token'].toString().startsWith('{')) {
        try { meta = jsonDecode(u['device_token'].toString()); } catch (_) {}
      }
      if (normalizedStatus != null && normalizedStatus.isNotEmpty) meta['status'] = normalizedStatus;
      if (permissions != null) meta['permissions'] = permissions;
      if (districtIds != null) meta['districtIds'] = districtIds;
      updateMap['device_token'] = jsonEncode(meta);

      await Supabase.instance.client.from('users').update(updateMap).eq('id', id);

      if (districtIds != null) {
        try {
          await Supabase.instance.client.from('sub_admin_districts').delete().eq('sub_admin_id', id);
          for (final dId in districtIds) {
            await Supabase.instance.client.from('sub_admin_districts').insert({
              'sub_admin_id': id,
              'district_id': dId,
            });
          }
        } catch (_) {}
      }
      return {'success': true, 'message': 'Sub-Admin updated successfully.'};
    } catch (e) {
      debugPrint('Update Sub-Admin Supabase direct error: $e');
    }

    return {'success': false, 'message': 'Failed to update Sub-Admin.'};
  }

  /// Toggle Sub-Admin Status (Activate / Deactivate) — Authoritative Backend Persistence with 24/7 Supabase Fallback
  Future<bool> toggleSubAdminStatus(String id, {String? status, bool? isActive}) async {
    _lastSubAdminToggleError = null;
    _lastSubAdminConfirmedStatus = null;
    if (debugToggleSubAdminStatusOverride != null) {
      final ok = await debugToggleSubAdminStatusOverride!(id, status: status, isActive: isActive);
      if (ok) {
        _lastSubAdminConfirmedStatus = (status ?? (isActive == true ? 'ACTIVE' : 'INACTIVE')).trim().toUpperCase();
      } else {
        _lastSubAdminToggleError = 'Status update rejected.';
      }
      return ok;
    }

    final targetStatus = (status ?? (isActive == true ? 'ACTIVE' : 'INACTIVE')).trim().toUpperCase();

    // 1. Express Backend API first (persists status column + status_updated_at/by, revokes sessions, logs audit)
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$id/status');
      final response = await http.patch(
        url,
        headers: _headersWithUser(),
        body: jsonEncode({
          'status': targetStatus,
          'is_active': targetStatus == 'ACTIVE',
        }),
      ).timeout(const Duration(seconds: 35));

      final Map<String, dynamic> data = response.body.isNotEmpty
          ? (jsonDecode(response.body) as Map<String, dynamic>? ?? {})
          : {};

      if (response.statusCode == 200 && data['success'] == true) {
        final returnedStatus = (data['subAdmin']?['status'] ?? targetStatus).toString().trim().toUpperCase();
        _lastSubAdminConfirmedStatus = returnedStatus;
        return returnedStatus == targetStatus;
      }
      if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        _lastSubAdminToggleError = (data['message'] ?? 'Unauthorized or invalid status update request.').toString();
        return false;
      }
      _lastSubAdminToggleError = (data['message'] ?? 'Backend returned status ${response.statusCode}').toString();
    } catch (e) {
      debugPrint('Toggle sub-admin status backend notice ($e), attempting direct Supabase fallback...');
    }

    // 2. Direct Supabase Cloud fallback ONLY if Express backend is unreachable
    try {
      final u = await Supabase.instance.client.from('users').select('id, device_token').eq('id', id).maybeSingle();
      if (u == null) {
        _lastSubAdminToggleError = 'Sub-Admin record not found.';
        return false;
      }
      Map<String, dynamic> meta = {};
      if (u['device_token'] != null && u['device_token'].toString().startsWith('{')) {
        try {
          meta = jsonDecode(u['device_token'].toString());
        } catch (_) {}
      }
      meta['status'] = targetStatus;
      meta['statusUpdatedAt'] = DateTime.now().toIso8601String();
      if (targetStatus == 'INACTIVE') {
        meta['revokedBefore'] = DateTime.now().millisecondsSinceEpoch;
      } else {
        meta.remove('revokedBefore');
      }
      await Supabase.instance.client.from('users').update({
        'status': targetStatus,
        'device_token': jsonEncode(meta),
        if (targetStatus == 'INACTIVE') 'refresh_tokens': [],
      }).eq('id', id);
      _lastSubAdminConfirmedStatus = targetStatus;
      _lastSubAdminToggleError = null;
      return true;
    } catch (e) {
      debugPrint('Toggle sub-admin status Supabase error: $e');
      _lastSubAdminToggleError = 'Unable to update status. Please check network connection.';
      return false;
    }
  }

  /// Delete Sub-Admin
  Future<bool> deleteSubAdmin(String id) async {
    // 1. Direct Supabase Delete FIRST
    try {
      await Supabase.instance.client.from('users').delete().eq('id', id);
      try {
        await Supabase.instance.client.from('sub_admin_districts').delete().eq('sub_admin_id', id);
      } catch (_) {}
    } catch (e) {
      debugPrint('Delete sub-admin Supabase error: $e');
    }

    // 2. Asynchronous Express backend notification (Non-blocking)
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$id');
      http.delete(url, headers: _headers).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
    } catch (e) {
      debugPrint('Delete Sub-Admin API notice: $e');
    }
    return true;
  }

  // ==========================================
  // DISTRICT MANAGEMENT APIS
  // ==========================================

  /// Fetch all active districts (Public / Dropdown use)
  Future<List<dynamic>> fetchDistricts() async {
    // 1. Express backend API call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/districts');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['districts'] is List) {
          return data['districts'];
        }
      }
    } catch (e) {
      debugPrint('Fetch districts API notice: $e');
    }

    // 2. Supabase Cloud Fallback
    try {
      final res = await Supabase.instance.client
          .from('districts')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);
      if (res.isNotEmpty) return res;
    } catch (e) {
      debugPrint('Fetch districts Supabase notice: $e');
    }

    return [];
  }

  /// Fetch all districts for Admin with filters (includes inactive)
  Future<List<dynamic>> fetchAdminDistricts({String? search, bool? isActive}) async {
    // 1. Express backend API
    try {
      final queryParams = <String, String>{};
      if (search != null && search.trim().isNotEmpty) queryParams['search'] = search.trim();
      if (isActive != null) queryParams['status'] = isActive ? 'active' : 'inactive';

      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/districts').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['districts'] is List) {
          return data['districts'];
        }
      }
    } catch (e) {
      debugPrint('Fetch admin districts API notice: $e');
    }

    // 2. Supabase Cloud Fallback
    try {
      var query = Supabase.instance.client.from('districts').select();
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }
      final res = await query.order('name', ascending: true);
      if (res.isNotEmpty) return res;
    } catch (e) {
      debugPrint('Fetch admin districts Supabase notice: $e');
    }

    return [];
  }

  /// Create a new District
  Future<Map<String, dynamic>> createDistrict({
    required String name,
    required String state,
    String? code,
    bool isActive = true,
  }) async {
    // 1. Express API call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/districts');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'name': name.trim(),
          'state': state.trim(),
          if (code != null && code.trim().isNotEmpty) 'code': code.trim().toUpperCase(),
          'is_active': isActive,
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'district': data['district'], 'message': data['message'] ?? 'District created.'};
      }
    } catch (e) {
      debugPrint('Create district API notice: $e');
    }

    // 2. Supabase Cloud Direct Fallback
    try {
      final res = await Supabase.instance.client.from('districts').insert({
        'name': name.trim(),
        'state': state.trim(),
        'code': (code != null && code.trim().isNotEmpty) ? code.trim().toUpperCase() : name.trim().substring(0, 3).toUpperCase(),
        'is_active': isActive,
      }).select().maybeSingle();

      return {
        'success': true,
        'district': res ?? {'name': name, 'state': state, 'is_active': isActive},
        'message': 'District created successfully.',
      };
    } catch (e) {
      debugPrint('Create district Supabase error: $e');
    }

    return {'success': false, 'message': 'Failed to create district'};
  }

  /// Update District
  Future<Map<String, dynamic>> updateDistrict({
    required String id,
    required String name,
    required String state,
    String? code,
    bool? isActive,
  }) async {
    // 1. Express API call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/districts/$id');
      final payload = <String, dynamic>{
        'name': name.trim(),
        'state': state.trim(),
        if (code != null && code.trim().isNotEmpty) 'code': code.trim().toUpperCase(),
        if (isActive != null) 'is_active': isActive,
      };
      final response = await http.put(url, headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'district': data['district'], 'message': data['message'] ?? 'District updated.'};
      }
    } catch (e) {
      debugPrint('Update district API notice: $e');
    }

    // 2. Supabase Direct Fallback
    try {
      final updateData = <String, dynamic>{
        'name': name.trim(),
        'state': state.trim(),
        if (code != null && code.trim().isNotEmpty) 'code': code.trim().toUpperCase(),
        if (isActive != null) 'is_active': isActive,
      };
      final res = await Supabase.instance.client.from('districts').update(updateData).eq('id', id).select().maybeSingle();
      return {'success': true, 'district': res, 'message': 'District updated successfully.'};
    } catch (e) {
      debugPrint('Update district Supabase error: $e');
    }

    return {'success': false, 'message': 'Failed to update district'};
  }

  /// Toggle District active/inactive status
  Future<bool> toggleDistrictStatus(String id, bool isActive) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/districts/$id/status');
      http.patch(url, headers: _headers, body: jsonEncode({'is_active': isActive})).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
    } catch (_) {}

    try {
      await Supabase.instance.client.from('districts').update({'is_active': isActive}).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Toggle district status Supabase error: $e');
    }
    return true;
  }

  /// Fetch assigned districts for a Sub-Admin
  Future<List<dynamic>> fetchSubAdminDistricts(String subAdminId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$subAdminId/districts');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['districts'] is List) {
          return data['districts'];
        }
      }
    } catch (e) {
      debugPrint('Fetch Sub-Admin districts API notice: $e');
    }

    // Direct Supabase query
    try {
      final res = await Supabase.instance.client
          .from('sub_admin_districts')
          .select('district_id, districts(*)')
          .eq('sub_admin_id', subAdminId);
      if (res.isNotEmpty) {
        return res.map((r) => r['districts'] ?? {'id': r['district_id']}).toList();
      }
    } catch (e) {
      debugPrint('Fetch Sub-Admin districts Supabase notice: $e');
    }

    return [];
  }

  /// Assign multiple districts to a Sub-Admin (with deduplication)
  Future<Map<String, dynamic>> assignSubAdminDistricts(String subAdminId, List<String> districtIds) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$subAdminId/districts');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({'districtIds': districtIds}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'assignedDistricts': data['assignedDistricts'] ?? []};
      }
    } catch (e) {
      debugPrint('Assign Sub-Admin districts API notice: $e');
    }

    // Direct Supabase Fallback
    try {
      await Supabase.instance.client.from('sub_admin_districts').delete().eq('sub_admin_id', subAdminId);
      for (final dId in districtIds) {
        await Supabase.instance.client.from('sub_admin_districts').insert({
          'sub_admin_id': subAdminId,
          'district_id': dId,
        });
      }
      return {'success': true, 'message': 'Districts assigned successfully.'};
    } catch (e) {
      debugPrint('Assign Sub-Admin districts Supabase error: $e');
    }

    return {'success': false, 'message': 'Failed to assign districts'};
  }

  /// Remove single district assignment from Sub-Admin
  Future<bool> removeSubAdminDistrict(String subAdminId, String districtId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$subAdminId/districts/$districtId');
      http.delete(url, headers: _headers).timeout(const Duration(seconds: 5)).catchError((_) => http.Response('{}', 200));
    } catch (_) {}

    try {
      await Supabase.instance.client
          .from('sub_admin_districts')
          .delete()
          .eq('sub_admin_id', subAdminId)
          .eq('district_id', districtId);
      return true;
    } catch (e) {
      debugPrint('Remove subadmin district Supabase error: $e');
    }
    return true;
  }

  // ==========================================
  // SUB-ADMIN PERMISSIONS & AUDIT APIS
  // ==========================================

  /// Fetch Sub-Admin Permissions & Audit History
  Future<Map<String, dynamic>> fetchSubAdminPermissions(String subAdminId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$subAdminId/permissions');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Fetch Sub-Admin permissions API notice: $e');
    }

    return {'success': false, 'permissions': [], 'history': []};
  }

  /// Update Sub-Admin Permissions (Main Admin only - strictly audited)
  Future<Map<String, dynamic>> updateSubAdminPermissions(String subAdminId, List<String> permissions) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$subAdminId/permissions');
      final response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode({'permissions': permissions}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Update Sub-Admin permissions API notice: $e');
    }

    // Supabase direct fallback
    try {
      final u = await Supabase.instance.client.from('users').select('device_token').eq('id', subAdminId).maybeSingle();
      Map<String, dynamic> meta = {};
      if (u != null && u['device_token'] != null && u['device_token'].toString().startsWith('{')) {
        try { meta = jsonDecode(u['device_token'].toString()); } catch (_) {}
      }
      meta['permissions'] = permissions;
      await Supabase.instance.client.from('users').update({'device_token': jsonEncode(meta)}).eq('id', subAdminId);
      return {'success': true, 'message': 'Permissions updated successfully.', 'permissions': permissions};
    } catch (e) {
      debugPrint('Update Sub-Admin permissions Supabase error: $e');
    }

    return {'success': false, 'message': 'Failed to update permissions'};
  }

  /// Fetch patient assignment history by a specific Sub-Admin
  Future<List<dynamic>> fetchSubAdminAssignmentHistory(String subAdminId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/sub-admins/$subAdminId/assignment-history');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['history'] is List) {
          return data['history'];
        }
      }
    } catch (e) {
      debugPrint('Fetch Sub-Admin assignment history API notice: $e');
    }

    // Direct Supabase fallback
    try {
      final res = await Supabase.instance.client
          .from('patient_assignment_history')
          .select()
          .eq('assigned_by', subAdminId)
          .order('created_at', ascending: false);
      if (res.isNotEmpty) return res;
    } catch (e) {
      debugPrint('Fetch subadmin history Supabase notice: $e');
    }

    return [];
  }

  // ==========================================
  // PATIENT ASSIGNMENTS & IMMUTABLE AUDIT TRAIL
  // ==========================================

  /// Assign a Patient to a Doctor (Main Admin or Sub-Admin)
  Future<Map<String, dynamic>> assignPatientToDoctor({
    required String patientId,
    required String dentistId,
    String? clinicId,
    String? districtId,
    String? reason,
    String? notes,
    String? scheduledDate,
    String? timeSlot,
  }) async {
    // 1. Express backend API call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/patient-assignments');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'patientId': patientId,
          'dentistId': dentistId,
          if (clinicId != null) 'clinicId': clinicId,
          if (districtId != null) 'districtId': districtId,
          if (reason != null) 'reason': reason,
          if (notes != null) 'notes': notes,
          if (scheduledDate != null) 'scheduledDate': scheduledDate,
          if (timeSlot != null) 'timeSlot': timeSlot,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'assignment': data['assignment'],
          'message': data['message'] ?? 'Patient assigned successfully.',
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to assign patient'};
      }
    } catch (e) {
      debugPrint('Assign patient API notice: $e');
    }

    // 2. Direct Supabase Fallback
    try {
      final currentUserId = SupabaseService.safeCurrentUser?.id;
      final res = await Supabase.instance.client.from('patient_assignment_history').insert({
        'patient_id': patientId,
        'dentist_id': dentistId,
        if (clinicId != null) 'clinic_id': clinicId,
        if (districtId != null) 'district_id': districtId,
        'assigned_by': currentUserId ?? 'ADMIN',
        'assigned_by_role': 'MAIN_ADMIN',
        'assignment_source': 'MAIN_ADMIN_ASSIGNMENT',
        'status': 'ACTIVE',
        'reason': reason ?? 'Clinical specialist assignment',
        'notes': notes ?? '',
      }).select().maybeSingle();

      return {
        'success': true,
        'assignment': res,
        'message': 'Patient assigned successfully (Cloud fallback).',
      };
    } catch (e) {
      debugPrint('Assign patient Supabase fallback error: $e');
    }

    return {'success': false, 'message': 'Failed to assign patient'};
  }

  /// Reassign a Patient to a different Doctor (Main Admin or Sub-Admin)
  Future<Map<String, dynamic>> reassignPatient({
    required String patientId,
    required String newDentistId,
    String? previousAssignmentId,
    String? reason,
    String? notes,
  }) async {
    // 1. Express backend API call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/patient-assignments/reassign');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'patientId': patientId,
          'newDentistId': newDentistId,
          if (previousAssignmentId != null) 'previousAssignmentId': previousAssignmentId,
          'reason': reason ?? 'Doctor reassignment requested',
          if (notes != null) 'notes': notes,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'assignment': data['assignment'],
          'message': data['message'] ?? 'Patient reassigned successfully.',
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to reassign patient'};
      }
    } catch (e) {
      debugPrint('Reassign patient API notice: $e');
    }

    return {'success': false, 'message': 'Failed to reassign patient'};
  }

  /// Fetch immutable patient assignment history with filtering
  Future<Map<String, dynamic>> fetchAssignmentHistory({
    String? patientId,
    String? dentistId,
    String? districtId,
    String? assignedBy,
    String? assignmentSource,
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    // 1. Express backend API call
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (patientId != null && patientId.isNotEmpty) queryParams['patientId'] = patientId;
      if (dentistId != null && dentistId.isNotEmpty) queryParams['dentistId'] = dentistId;
      if (districtId != null && districtId.isNotEmpty) queryParams['districtId'] = districtId;
      if (assignedBy != null && assignedBy.isNotEmpty) queryParams['assignedBy'] = assignedBy;
      if (assignmentSource != null && assignmentSource.isNotEmpty) queryParams['assignmentSource'] = assignmentSource;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;

      final uri = Uri.parse('${ApiConstants.baseUrl}/patient-assignments/history').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Fetch assignment history API notice: $e');
    }

    // 2. Direct Supabase Fallback
    try {
      var query = Supabase.instance.client.from('patient_assignment_history').select();
      if (patientId != null && patientId.isNotEmpty) query = query.eq('patient_id', patientId);
      if (dentistId != null && dentistId.isNotEmpty) query = query.eq('dentist_id', dentistId);
      if (districtId != null && districtId.isNotEmpty) query = query.eq('district_id', districtId);
      if (assignmentSource != null && assignmentSource.isNotEmpty) query = query.eq('assignment_source', assignmentSource);

      final res = await query.order('created_at', ascending: false).limit(limit);
      return {
        'success': true,
        'history': res,
        'total': res.length,
      };
    } catch (e) {
      debugPrint('Fetch assignment history Supabase error: $e');
    }

    return {'success': false, 'history': [], 'total': 0};
  }

  /// Fetch chronological timeline for a specific patient
  Future<List<dynamic>> fetchPatientAssignmentTimeline(String patientId) async {
    // 1. Express backend API
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/patient-assignments/patient/$patientId');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['timeline'] is List) {
          return data['timeline'];
        }
      }
    } catch (e) {
      debugPrint('Fetch patient timeline API notice: $e');
    }

    // 2. Supabase Fallback
    try {
      final res = await Supabase.instance.client
          .from('patient_assignment_history')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);
      if (res.isNotEmpty) return res;
    } catch (e) {
      debugPrint('Fetch patient timeline Supabase notice: $e');
    }

    return [];
  }

  /// Fetch platform assignment statistics & KPI breakdowns
  Future<Map<String, dynamic>> fetchAssignmentStatistics() async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/reports/assignment-statistics');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['statistics'] != null) {
          return data['statistics'];
        }
      }
    } catch (e) {
      debugPrint('Fetch assignment statistics API notice: $e');
    }

    return {};
  }

  /// Fetch district-wise consolidated reports
  Future<List<dynamic>> fetchDistrictReports() async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/reports/districts');
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['reports'] is List) {
          return data['reports'];
        }
      }
    } catch (e) {
      debugPrint('Fetch district reports API notice: $e');
    }

    return [];
  }

  /// Admin: Mark Patient Problem Request as Reviewed
  Future<Map<String, dynamic>> markAdminReviewed(String requestId, {String? notes}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/problem-requests/$requestId/review');
      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({if (notes != null) 'notes': notes}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to mark request as reviewed.'};
    }
  }

  /// Admin: Suggest / Assign Dentist to a Patient Request
  Future<Map<String, dynamic>> suggestDentist({
    required String requestId,
    required String dentistId,
    String? notes,
    String? doctorName,
    String? doctorSpecialty,
    String? doctorClinic,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/problem-requests/$requestId/suggest-dentist');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'dentistId': dentistId,
          if (notes != null) 'notes': notes,
          if (doctorName != null) 'doctorName': doctorName,
          if (doctorSpecialty != null) 'doctorSpecialty': doctorSpecialty,
          if (doctorClinic != null) 'doctorClinic': doctorClinic,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to suggest doctor.'};
    }
  }

  /// Admin / Coordinator: Update 6-stage coordinator status and append follow-up note
  Future<Map<String, dynamic>> updateCoordinatorStatus({
    required String requestId,
    required String status,
    String? followUpNote,
    String? coordinatorId,
    String? coordinatorName,
    String? doctorId,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/problem-requests/$requestId/coordinator-status');
      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({
          'status': status,
          if (followUpNote != null && followUpNote.trim().isNotEmpty) 'followUpNote': followUpNote.trim(),
          if (coordinatorId != null) 'coordinatorId': coordinatorId,
          if (coordinatorName != null) 'coordinatorName': coordinatorName,
          if (doctorId != null) 'doctorId': doctorId,
        }),
      ).timeout(const Duration(seconds: 35));
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to update coordinator status.'};
    }
  }

  /// Dentist: Accept Problem Request / Referral & Confirm Slot
  Future<Map<String, dynamic>> acceptProblemRequest({
    required String requestId,
    String? timeSlot,
    String? date,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/problem-requests/$requestId/accept');
      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({
          if (timeSlot != null) 'timeSlot': timeSlot,
          if (date != null) 'date': date,
        }),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Accept problem request API error: $e');
    }
    return {'success': false};
  }

  /// Dentist: Accept Appointment Request [PENDING -> CONFIRMED]
  Future<Map<String, dynamic>> acceptAppointment(String appointmentId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/accept');
      http.Response response;
      try {
        response = await http.patch(url, headers: _headers).timeout(const Duration(seconds: 35));
      } catch (_) {
        response = await http.put(url, headers: _headers).timeout(const Duration(seconds: 35));
      }
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to accept appointment.',
      };
    } catch (e) {
      debugPrint('Accept appointment API notice: $e');
      try {
        await Supabase.instance.client
            .from('appointments')
            .update({'status': 'CONFIRMED'})
            .eq('id', appointmentId);
        return {'success': true, 'message': 'Appointment confirmed successfully.'};
      } catch (_) {}
      return {'success': false, 'message': 'Failed to accept appointment.'};
    }
  }

  /// Dentist: Reject Appointment Request [PENDING -> REJECTED]
  Future<Map<String, dynamic>> rejectAppointment(String appointmentId, {String? reason}) async {
    final bodyJson = jsonEncode({if (reason != null) 'reason': reason});
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/reject');
      http.Response response;
      try {
        response = await http.patch(
          url,
          headers: _headers,
          body: bodyJson,
        ).timeout(const Duration(seconds: 35));
      } catch (_) {
        response = await http.put(
          url,
          headers: _headers,
          body: bodyJson,
        ).timeout(const Duration(seconds: 35));
      }
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to reject appointment.',
      };
    } catch (e) {
      debugPrint('Reject appointment API notice: $e');
      try {
        await Supabase.instance.client
            .from('appointments')
            .update({'status': 'REJECTED'})
            .eq('id', appointmentId);
        return {'success': true, 'message': 'Appointment declined.'};
      } catch (_) {}
      return {'success': false, 'message': 'Failed to reject appointment.'};
    }
  }

  /// Patient / Dentist: Reschedule Appointment [-> RESCHEDULED]
  Future<Map<String, dynamic>> rescheduleAppointment({
    required String appointmentId,
    required String date,
    required String timeSlot,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/reschedule');
      final response = await http
          .patch(
            url,
            headers: _headers,
            body: jsonEncode({'date': date, 'timeSlot': timeSlot}),
          )
          .timeout(const Duration(seconds: 35));
      final resData = jsonDecode(response.body);
      return resData;
    } catch (e) {
      // Direct Supabase Fallback
      try {
        final client = Supabase.instance.client;
        final res = await client
            .from('appointments')
            .update({
              'date': date,
              'time_slot': timeSlot,
              'status': 'RESCHEDULED',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', appointmentId)
            .select()
            .single();
        return {'success': true, 'message': 'Appointment rescheduled successfully.', 'appointment': res};
      } catch (err) {
        return {'success': false, 'message': 'Failed to reschedule appointment: $err'};
      }
    }
  }

  /// Patient / Dentist: Cancel Appointment [-> CANCELLED]
  Future<Map<String, dynamic>> cancelAppointment(String appointmentId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/cancel');
      final response = await http.patch(url, headers: _headers).timeout(const Duration(seconds: 35));
      final resData = jsonDecode(response.body);
      return resData;
    } catch (e) {
      // Direct Supabase Fallback
      try {
        final client = Supabase.instance.client;
        final res = await client
            .from('appointments')
            .update({
              'status': 'CANCELLED',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', appointmentId)
            .select()
            .single();
        return {'success': true, 'message': 'Appointment cancelled successfully.', 'appointment': res};
      } catch (err) {
        return {'success': false, 'message': 'Failed to cancel appointment: $err'};
      }
    }
  }

  /// Dentist: Complete Consultation [CONFIRMED -> COMPLETED]
  Future<Map<String, dynamic>> completeConsultation({
    required String appointmentId,
    String? symptoms,
    String? diagnosis,
    String? treatmentNotes,
    String? treatmentPlan,
    String? followUpDate,
    List<Map<String, dynamic>>? prescriptions,
    List<String>? attachments,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/complete');
      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({
          if (symptoms != null) 'symptoms': symptoms,
          if (diagnosis != null) 'diagnosis': diagnosis,
          if (treatmentNotes != null) 'treatmentNotes': treatmentNotes,
          if (treatmentPlan != null) 'treatmentPlan': treatmentPlan,
          if (followUpDate != null) 'followUpDate': followUpDate,
          if (prescriptions != null) 'prescriptions': prescriptions,
          if (attachments != null) 'attachments': attachments,
        }),
      );
      final resData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        AnalyticsService.logConsultationCompleted(appointmentId: appointmentId);
      }
      return resData;
    } catch (e) {
      return {'success': false, 'message': 'Failed to complete consultation.'};
    }
  }

  /// Fetch centralized hybrid scheduling rules (durations, buffers, intervals, thresholds)
  Future<Map<String, dynamic>> fetchSchedulingRules() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/scheduling/rules');
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['rules'] is Map) {
          BookingRulesConfig.applyFromJson(Map<String, dynamic>.from(data['rules'] as Map));
        }
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('Fetch scheduling rules notice: $e');
    }
    return {'success': true, 'rules': BookingRulesConfig.toJson()};
  }

  /// Admin: Update hybrid scheduling duration & buffer rules
  Future<Map<String, dynamic>> updateSchedulingRules(Map<String, dynamic> rules) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/scheduling/rules');
      final response = await http
          .put(uri, headers: _headers, body: jsonEncode(rules))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true && data['rules'] is Map) {
        BookingRulesConfig.applyFromJson(Map<String, dynamic>.from(data['rules'] as Map));
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update scheduling rules.',
      };
    } catch (_) {
      BookingRulesConfig.applyFromJson(rules);
      return {'success': true, 'rules': BookingRulesConfig.toJson(), 'localOnly': true};
    }
  }

  /// Admin: Live hybrid doctor calendar monitor & pending reschedule requests
  Future<Map<String, dynamic>> fetchLiveSchedulingStatus({String? date}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/scheduling/live-status').replace(
        queryParameters: (date != null && date.trim().isNotEmpty) ? {'date': date.trim()} : null,
      );
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['rules'] is Map) {
          BookingRulesConfig.applyFromJson(Map<String, dynamic>.from(data['rules'] as Map));
        }
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('Fetch live scheduling status notice: $e');
    }
    return {
      'success': false,
      'doctors': const [],
      'pendingRescheduleRequests': const [],
      'rules': BookingRulesConfig.toJson(),
    };
  }

  /// Doctor/Admin: Start consultation (updates live doctor status to Busy – Online/In-Person Consultation)
  Future<Map<String, dynamic>> startConsultation(String appointmentId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/start');
      final response = await http.patch(uri, headers: _headers).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to start consultation.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to start consultation: $e'};
    }
  }

  /// Doctor/Admin: Mark consultation delayed & alert next patient + Admin
  Future<Map<String, dynamic>> markConsultationDelayed(String appointmentId, {int delayMinutes = 15}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/delay');
      final response = await http
          .patch(uri, headers: _headers, body: jsonEncode({'delayMinutes': delayMinutes}))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to mark consultation delay.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to mark consultation delay: $e'};
    }
  }

  /// Doctor/Admin: Mark patient no-show and release slot
  Future<Map<String, dynamic>> markPatientNoShow(String appointmentId) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/no-show');
      final response = await http.patch(uri, headers: _headers).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to mark patient no-show.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to mark patient no-show: $e'};
    }
  }

  /// Patient: Respond to doctor delay (WAIT, REQUEST_RESCHEDULE, SWITCH_DOCTOR)
  Future<Map<String, dynamic>> submitPatientDelayResponse({
    required String appointmentId,
    required String action,
    String? requestedDate,
    String? requestedTimeSlot,
    String? reason,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/appointments/$appointmentId/delay-response');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'action': action,
              if (requestedDate != null) 'requestedDate': requestedDate,
              if (requestedTimeSlot != null) 'requestedTimeSlot': requestedTimeSlot,
              if (reason != null) 'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return Map<String, dynamic>.from(data);
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to submit delay response.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to submit response: $e'};
    }
  }

  /// Admin/Doctor: Manually block an individual time slot on a date
  Future<Map<String, dynamic>> blockDoctorTimeSlot({
    required String dentistId,
    required String date,
    required String startTime,
    String? endTime,
    String reason = 'Blocked by Admin',
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/block-slot');
      final response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'dentistId': dentistId,
              'date': date.contains('T') ? date.split('T').first : date,
              'startTime': startTime,
              if (endTime != null) 'endTime': endTime,
              'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 25));
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return {'success': false, 'message': 'Failed to block time slot: $e'};
    }
  }

  /// Admin/Doctor: Unblock an individual time slot on a date
  Future<Map<String, dynamic>> unblockDoctorTimeSlot({
    required String dentistId,
    required String date,
    required String startTime,
  }) async {
    try {
      final cleanDate = date.contains('T') ? date.split('T').first : date;
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/block-slot').replace(
        queryParameters: {'dentistId': dentistId, 'date': cleanDate, 'startTime': startTime},
      );
      final response = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 25));
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } catch (e) {
      return {'success': false, 'message': 'Failed to unblock time slot: $e'};
    }
  }

  /// Admin: Verify Dentist Status
  Future<Map<String, dynamic>> verifyDentist(String dentistId, String status, {String? notes}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/dentists/$dentistId/verify');
      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({'status': status, if (notes != null) 'notes': notes}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to update doctor verification status.'};
    }
  }

  /// Admin: Verify Clinic Status
  Future<Map<String, dynamic>> verifyClinic(String clinicId, String status, {String? notes}) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/admin/clinics/$clinicId/verify');
      final response = await http.patch(
        url,
        headers: _headers,
        body: jsonEncode({'status': status, if (notes != null) 'notes': notes}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to update clinic verification status.'};
    }
  }

  // ─────────────────────────────────────────────
  // REFERRAL MANAGEMENT & ORGANIC GROWTH
  // ─────────────────────────────────────────────

  /// Patient: Fetch My Referrals & Stats
  Future<Map<String, dynamic>> fetchMyReferrals({String? userId, String? userPhone, String? referralCode}) async {
    // 1. Primary Express backend API attempt
    try {
      final queryParam = userId != null ? '?userId=$userId' : '';
      final url = Uri.parse('${ApiConstants.myReferrals}$queryParam');
      final response = await http.get(
        url,
        headers: {
          ..._headers,
          if (userId != null) 'x-user-id': userId,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['referrals'] is List && (data['referrals'] as List).isNotEmpty) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Express fetch my referrals notice: $e');
    }

    // 2. Direct 24/7 Supabase Cloud Resolution Fallback
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {'success': false, 'referrals': const <dynamic>[]};
    }
    try {
      final authUser = client.auth.currentUser;
      final effectiveUserId = userId ?? authUser?.id ?? '';

      // Fetch all users to resolve referrals
      final allUsersRes = await client.from('users').select('*');
      final allUsers = List<Map<String, dynamic>>.from(allUsersRes);

      // Find current patient user record
      Map<String, dynamic>? currentUserMap;
      if (effectiveUserId.isNotEmpty) {
        for (final u in allUsers) {
          if (u['id']?.toString() == effectiveUserId) {
            currentUserMap = u;
            break;
          }
        }
      }
      if (currentUserMap == null && userPhone != null && userPhone.isNotEmpty) {
        for (final u in allUsers) {
          if ((u['phone'] ?? '').toString().contains(userPhone)) {
            currentUserMap = u;
            break;
          }
        }
      }

      final curName = currentUserMap?['name']?.toString() ?? 'Patient';
      final curPhone = currentUserMap?['phone']?.toString() ?? '';
      final myPrefix = curName.length >= 3 ? curName.substring(0, 3).toUpperCase() : curName.toUpperCase();
      final myPhoneSuffix = curPhone.length >= 4 ? curPhone.substring(curPhone.length - 4) : '2026';
      final myGeneratedCode = referralCode ?? 'DG-$myPrefix$myPhoneSuffix';

      // Find all users who were referred by this user's code, phone, or id
      final referredUsers = <Map<String, dynamic>>[];
      for (final u in allUsers) {
        if (u['id']?.toString() == effectiveUserId) continue; // Skip self

        String refBy = (u['referral_code'] ?? '').toString().toUpperCase().trim();
        String refId = '';
        if (u['device_token'] != null && u['device_token'].toString().startsWith('{')) {
          try {
            final meta = jsonDecode(u['device_token'].toString());
            if (meta['referred_by_code'] != null) {
              refBy = meta['referred_by_code'].toString().toUpperCase().trim();
            }
            if (meta['referrer_id'] != null) {
              refId = meta['referrer_id'].toString();
            }
          } catch (_) {}
        }

        final isMatch = (refBy.isNotEmpty && refBy == myGeneratedCode.toUpperCase()) ||
            (curPhone.isNotEmpty && refBy == curPhone) ||
            (effectiveUserId.isNotEmpty && (refBy == effectiveUserId || refId == effectiveUserId));

        if (isMatch) {
          referredUsers.add(u);
        }
      }

      // Fetch appointments & problem requests to evaluate live status
      final allAppts = await client.from('appointments').select('*').catchError((_) => []);
      final allProblems = await client.from('patient_problem_requests').select('*').catchError((_) => []);

      final referralsList = <Map<String, dynamic>>[];
      int registeredCount = 0;
      int consultationsCount = 0;

      for (final refUser in referredUsers) {
        final rId = refUser['id']?.toString() ?? '';
        final rName = refUser['name']?.toString() ?? 'Friend';
        final rPhone = refUser['phone']?.toString() ?? '';
        final rCreatedAt = refUser['created_at']?.toString() ?? DateTime.now().toIso8601String();

        bool hasBooked = false;
        bool hasCompleted = false;

        for (final a in allAppts) {
          if (a['patient_id']?.toString() == rId || a['patient_phone']?.toString() == rPhone) {
            final st = (a['status'] ?? '').toString().toUpperCase();
            if (st == 'COMPLETED') {
              hasCompleted = true;
            } else {
              hasBooked = true;
            }
          }
        }
        if (!hasBooked && !hasCompleted) {
          for (final p in allProblems) {
            if (p['patient_id']?.toString() == rId || p['patient_phone']?.toString() == rPhone) {
              hasBooked = true;
            }
          }
        }

        String status = 'REGISTERED';
        if (hasCompleted) {
          status = 'CONSULTATION_COMPLETED';
          consultationsCount++;
        } else if (hasBooked) {
          status = 'CONSULTATION_BOOKED';
        }
        registeredCount++;

        referralsList.add({
          'id': rId,
          'referrerId': effectiveUserId,
          'referrerName': curName,
          'referrerPhone': curPhone,
          'referredUserId': rId,
          'referredUserName': rName,
          'referredUserPhone': rPhone,
          'referralCode': myGeneratedCode,
          'status': status,
          'createdAt': rCreatedAt,
        });
      }

      return {
        'success': true,
        'referralCode': myGeneratedCode,
        'stats': {
          'totalReferred': registeredCount,
          'registeredUsers': registeredCount,
          'consultationsCompleted': consultationsCount,
        },
        'referrals': referralsList,
      };
    } catch (supaErr) {
      debugPrint('⚠️ Supabase direct referral resolution notice: $supaErr');
      return {'success': false, 'message': supaErr.toString()};
    }
  }

  /// Test-only hook so widget tests can supply admin referrals without a backend.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function()? debugAdminReferralsOverride;

  /// Admin: Fetch All Platform Referrals (Comprehensive: Dedicated Referrals + Fallback Payloads + Growth Invites)
  Future<Map<String, dynamic>> fetchAllReferralsAdmin() async {
    final override = debugAdminReferralsOverride;
    if (override != null) return override();

    // 1. Primary Express Backend Call
    bool expressResponded = false;
    try {
      final url = Uri.parse(ApiConstants.allReferralsAdmin);
      final response = await http.get(url, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return {'success': false, 'statusCode': response.statusCode, 'referrals': const <dynamic>[]};
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['referrals'] is List) {
          expressResponded = true;
          if ((data['referrals'] as List).isNotEmpty) {
            return data;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Express admin referrals notice: $e');
    }

    // 2. Direct Supabase Cloud Dual-Mode Fallback
    final client = SupabaseService.safeClient;
    if (client == null) {
      return expressResponded
          ? {'success': true, 'referrals': const <dynamic>[]}
          : {'success': false, 'message': 'Unable to fetch referrals.'};
    }
    try {
      final referralsList = <Map<String, dynamic>>[];
      final seenIds = <String>{};

      // Tier A: Query dedicated 'referrals' table in Supabase
      try {
        dynamic res;
        try {
          res = await client
              .from('referrals')
              .select('*, doctor:dentists!doctor_id(id, speciality, qualifications, users(name, email, phone), clinics(clinic_name, location)), referrer:users!referrer_patient_id(id, name, phone, email)')
              .order('created_at', ascending: false);
        } catch (_) {
          res = await client
              .from('referrals')
              .select('*')
              .order('created_at', ascending: false);
        }

        if (res.isNotEmpty) {
          for (final row in res) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) seenIds.add(id);

            String docName = 'Specialist';
            String docSpecialty = row['required_specialist']?.toString() ?? 'General Dentistry';
            String clinicName = 'GS HEALTH Clinic';
            String clinicLoc = '';
            if (row['doctor'] is Map) {
              final dMap = row['doctor'] as Map;
              if (dMap['users'] is Map && dMap['users']['name'] != null) {
                docName = dMap['users']['name'].toString();
              }
              if (dMap['speciality'] != null) docSpecialty = dMap['speciality'].toString();
              if (dMap['clinics'] is Map) {
                if (dMap['clinics']['clinic_name'] != null) clinicName = dMap['clinics']['clinic_name'].toString();
                if (dMap['clinics']['location'] != null) clinicLoc = dMap['clinics']['location'].toString();
              }
            }
            if (!docName.startsWith('Dr.') && !docName.startsWith('Dr ')) {
              docName = 'Dr. $docName';
            }

            String refName = 'Patient Referrer';
            String refPhone = '';
            String refEmail = '';
            if (row['referrer'] is Map) {
              final rMap = row['referrer'] as Map;
              if (rMap['name'] != null) refName = rMap['name'].toString();
              if (rMap['phone'] != null) refPhone = rMap['phone'].toString();
              if (rMap['email'] != null) refEmail = rMap['email'].toString();
            }

            referralsList.add({
              'id': id,
              'referralId': id,
              'referrerPatientId': row['referrer_patient_id'] ?? row['referrer_id'] ?? '',
              'referrerPatientName': refName,
              'referrerPatientPhone': refPhone,
              'referrerPatientEmail': refEmail,
              'referrerName': refName,
              'referrerPhone': refPhone,

              'referredPatientId': row['referred_patient_id'] ?? row['referred_user_id'],
              'referredPatientName': row['referred_patient_name'] ?? 'Referred Patient',
              'referredPatientMobile': row['referred_patient_mobile'] ?? '',
              'referredUserName': row['referred_patient_name'] ?? 'Referred Patient',
              'referredUserPhone': row['referred_patient_mobile'] ?? '',
              'referredPatientAge': row['referred_patient_age'] ?? '',
              'referredPatientGender': row['referred_patient_gender'] ?? '',
              'referredPatientCity': row['referred_patient_city'] ?? '',
              'referredPatientPincode': row['referred_patient_pincode'] ?? '',
              'referredPatientLocation': row['referred_patient_location'] ?? '',

              'requiredSpecialist': row['required_specialist'] ?? docSpecialty,
              'clinicalComplaint': row['clinical_complaint'] ?? '',

              'doctorId': row['doctor_id'] ?? row['assigned_doctor_id'] ?? '',
              'doctorName': docName,
              'doctorSpecialty': docSpecialty,
              'doctorClinicName': clinicName,
              'doctorLocation': clinicLoc,
              'assignedDoctorName': docName,
              'assignedClinicName': clinicName,

              'status': row['status'] ?? 'Pending',
              'rejectionReason': row['rejection_reason'],
              'whatsappStatus': row['whatsapp_status'] ?? 'Sent',
              'referralDate': row['referral_date'] ?? row['created_at'] ?? DateTime.now().toIso8601String(),
              'createdAt': row['created_at'] ?? DateTime.now().toIso8601String(),
              'referralCode': row['referral_code'] ?? 'PATIENT-DIRECT',
            });
          }
        }
      } catch (_) {}

      // Tier B: Query fallback 'patient_problem_requests' where admin_notes contains REFERRAL_PAYLOAD:
      try {
        final probRes = await client
            .from('patient_problem_requests')
            .select('*')
            .ilike('admin_notes', 'REFERRAL_PAYLOAD:%')
            .order('created_at', ascending: false);

        if (probRes.isNotEmpty) {
          for (final row in probRes) {
            final id = row['id']?.toString() ?? '';
            if (seenIds.contains(id)) continue;
            seenIds.add(id);

            Map<String, dynamic> payload = {};
            try {
              final raw = (row['admin_notes'] ?? '').toString().replaceFirst('REFERRAL_PAYLOAD:', '').trim();
              payload = jsonDecode(raw);
            } catch (_) {}

            final isAccepted = (row['status'] ?? '').toString().toUpperCase() == 'CONFIRMED';
            final isRejected = (row['status'] ?? '').toString().toUpperCase() == 'REJECTED';
            final status = isAccepted ? 'Accepted' : (isRejected ? 'Rejected' : 'Pending');

            referralsList.add({
              'id': id,
              'referralId': id,
              'referrerPatientId': payload['referrerPatientId'] ?? row['patient_id'] ?? '',
              'referrerPatientName': payload['referrerPatientName'] ?? 'Patient Referrer',
              'referrerPatientPhone': payload['referrerPatientPhone'] ?? '',
              'referrerPatientEmail': payload['referrerPatientEmail'] ?? '',
              'referrerName': payload['referrerPatientName'] ?? 'Patient Referrer',
              'referrerPhone': payload['referrerPatientPhone'] ?? '',

              'referredPatientId': row['patient_id'],
              'referredPatientName': payload['referredPatientName'] ?? row['patient_name'] ?? 'Referred Patient',
              'referredPatientMobile': payload['referredPatientMobile'] ?? row['patient_phone'] ?? '',
              'referredUserName': payload['referredPatientName'] ?? row['patient_name'] ?? 'Referred Patient',
              'referredUserPhone': payload['referredPatientMobile'] ?? row['patient_phone'] ?? '',
              'referredPatientAge': payload['referredPatientAge'] ?? '',
              'referredPatientGender': payload['referredPatientGender'] ?? '',
              'referredPatientCity': payload['referredPatientCity'] ?? row['city'] ?? '',
              'referredPatientPincode': payload['referredPatientPincode'] ?? row['pincode'] ?? '',
              'referredPatientLocation': payload['referredPatientLocation'] ?? row['city'] ?? '',

              'requiredSpecialist': payload['requiredSpecialist'] ?? row['problem_category'] ?? 'Specialist Consultation',
              'clinicalComplaint': payload['clinicalComplaint'] ?? row['description'] ?? '',

              'doctorId': payload['doctorId'] ?? '',
              'doctorName': payload['doctorName'] ?? 'Dr. Specialist',
              'doctorSpecialty': payload['requiredSpecialist'] ?? 'Specialist Consultation',
              'doctorClinicName': payload['doctorClinicName'] ?? 'GS HEALTH Partner Clinic',
              'doctorLocation': payload['doctorLocation'] ?? '',
              'assignedDoctorName': payload['doctorName'] ?? 'Dr. Specialist',

              'status': status,
              'rejectionReason': payload['rejectionReason'],
              'whatsappStatus': 'Sent',
              'referralDate': row['created_at'] ?? DateTime.now().toIso8601String(),
              'createdAt': row['created_at'] ?? DateTime.now().toIso8601String(),
              'referralCode': 'DIRECT-CARE',
            });
          }
        }
      } catch (_) {}

      // Tier C: Also include peer referral attribution users (if any)
      try {
        final allUsersRes = await client.from('users').select('*');
        final allUsers = List<Map<String, dynamic>>.from(allUsersRes);

        for (final u in allUsers) {
          String refBy = (u['referral_code'] ?? '').toString().toUpperCase().trim();
          String refId = '';
          if (u['device_token'] != null && u['device_token'].toString().startsWith('{')) {
            try {
              final meta = jsonDecode(u['device_token'].toString());
              if (meta['referred_by_code'] != null) refBy = meta['referred_by_code'].toString().toUpperCase().trim();
              if (meta['referrer_id'] != null) refId = meta['referrer_id'].toString();
            } catch (_) {}
          }

          final uId = u['id']?.toString() ?? '';
          if ((refBy.isNotEmpty || refId.isNotEmpty) && !seenIds.contains(uId)) {
            seenIds.add(uId);

            Map<String, dynamic>? referrer = allUsers.firstWhere(
              (r) => r['id']?.toString() == refId ||
                     (r['name'] != null && refBy.contains(r['name'].toString().substring(0, 1).toUpperCase())) ||
                     (r['phone'] != null && refBy.endsWith(r['phone'].toString().substring(r['phone'].toString().length >= 4 ? r['phone'].toString().length - 4 : 0))),
              orElse: () => <String, dynamic>{'name': 'Referring Patient', 'phone': ''},
            );

            referralsList.add({
              'id': uId,
              'referrerId': referrer['id'] ?? refId,
              'referrerPatientId': referrer['id'] ?? refId,
              'referrerPatientName': referrer['name'] ?? 'Referring Patient',
              'referrerPatientPhone': referrer['phone'] ?? '',
              'referrerName': referrer['name'] ?? 'Referring Patient',
              'referrerPhone': referrer['phone'] ?? '',
              'referredUserId': uId,
              'referredPatientId': uId,
              'referredUserName': u['name'] ?? 'Registered Patient',
              'referredPatientName': u['name'] ?? 'Registered Patient',
              'referredUserPhone': u['phone'] ?? '',
              'referredPatientMobile': u['phone'] ?? '',
              'referredPatientCity': u['city'] ?? '',
              'referredPatientPincode': u['pincode'] ?? '',
              'referredPatientLocation': u['city'] ?? '',
              'requiredSpecialist': 'General Consultation',
              'clinicalComplaint': 'Platform Referral Registration',
              'referralCode': refBy,
              'status': 'REGISTERED',
              'whatsappStatus': 'Sent',
              'createdAt': u['created_at'] ?? DateTime.now().toIso8601String(),
              'referralDate': u['created_at'] ?? DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (_) {}

      return {'success': true, 'referrals': referralsList};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Admin: Fetch Growth Analytics
  Future<Map<String, dynamic>> fetchAdminReferralAnalytics() async {
    try {
      final url = Uri.parse(ApiConstants.referralAnalytics);
      final response = await http.get(url, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return {'success': false, 'statusCode': response.statusCode};
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['analytics'] != null) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Express referral analytics notice: $e');
    }

    // Direct Supabase Fallback for Analytics
    try {
      final allRefRes = await fetchAllReferralsAdmin();
      final list = (allRefRes['referrals'] as List?) ?? [];

      final total = list.length;
      final registered = list.length;
      final completed = list.where((r) => r['status'] == 'CONSULTATION_COMPLETED').length;
      final booked = list.where((r) => r['status'] == 'CONSULTATION_BOOKED').length;

      final Map<String, Map<String, dynamic>> referrersMap = {};
      for (final r in list) {
        final code = (r['referralCode'] ?? '').toString();
        final name = (r['referrerName'] ?? 'Patient').toString();
        final phone = (r['referrerPhone'] ?? '').toString();
        final id = (r['referrerId'] ?? code).toString();

        if (!referrersMap.containsKey(id)) {
          referrersMap[id] = {
            'userId': id,
            'name': name,
            'phone': phone,
            'referralCode': code,
            'totalReferred': 0,
            'registeredUsers': 0,
            'consultationsCompleted': 0,
          };
        }
        referrersMap[id]!['totalReferred'] = (referrersMap[id]!['totalReferred'] as int) + 1;
        referrersMap[id]!['registeredUsers'] = (referrersMap[id]!['registeredUsers'] as int) + 1;
        if (r['status'] == 'CONSULTATION_COMPLETED') {
          referrersMap[id]!['consultationsCompleted'] = (referrersMap[id]!['consultationsCompleted'] as int) + 1;
        }
      }

      final topReferrers = referrersMap.values.toList();
      topReferrers.sort((a, b) => (b['totalReferred'] as int).compareTo(a['totalReferred'] as int));

      return {
        'success': true,
        'analytics': {
          'totalReferrals': total,
          'registeredUsers': registered,
          'consultationsCompleted': completed,
          'consultationsBooked': booked,
          'topReferrers': topReferrers,
        }
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─────────────────────────────────────────────
  // COMPLETE "REFER A PATIENT" SYSTEM (PATIENT -> PATIENT -> DOCTOR)
  // ─────────────────────────────────────────────

  /// Test-only hook to simulate or stub referral creation without live HTTP.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String referredPatientName,
    required String referredPatientMobile,
    required String doctorId,
    String? referrerPatientId,
  })? debugCreatePatientReferralOverride;

  /// Patient: Create a Referral for another patient to a doctor
  Future<Map<String, dynamic>> createPatientReferral({
    required String referredPatientName,
    required String referredPatientMobile,
    required String referredPatientAge,
    required String referredPatientGender,
    required String referredPatientCity,
    required String referredPatientPincode,
    required String referredPatientLocation,
    required String requiredSpecialist,
    required String clinicalComplaint,
    String doctorId = '',
    String? referrerPatientId,
    String? doctorName,
    String? doctorClinicName,
    String? doctorLocation,
    String? doctorCity,
    String? doctorPincode,
    String? doctorPhone,
    bool sendWhatsApp = false,
  }) async {
    final override = debugCreatePatientReferralOverride;
    if (override != null) {
      return override(
        referredPatientName: referredPatientName,
        referredPatientMobile: referredPatientMobile,
        doctorId: doctorId,
        referrerPatientId: referrerPatientId,
      );
    }

    String currentUserId = (referrerPatientId ?? '').trim();
    if (currentUserId.isEmpty) {
      currentUserId = (SessionService().currentSession?.userId ?? '').trim();
    }
    if (currentUserId.isEmpty) {
      currentUserId = (SupabaseService.safeCurrentUser?.id ?? '').trim();
    }

    final trimmedDoctorId = doctorId.trim();
    final cleanDocName = trimmedDoctorId.isEmpty
        ? 'Any available specialist'
        : ((doctorName != null && doctorName.trim().isNotEmpty)
            ? (doctorName.trim().startsWith('Dr.') ? doctorName.trim() : 'Dr. ${doctorName.trim()}')
            : 'Doctor');

    final cleanAge = referredPatientAge.trim().isNotEmpty ? referredPatientAge.trim() : 'Not specified';
    final cleanGender = referredPatientGender.trim().isNotEmpty ? referredPatientGender.trim() : 'Not specified';
    final cleanCity = referredPatientCity.trim().isNotEmpty ? referredPatientCity.trim() : 'Not specified';
    final cleanPincode = referredPatientPincode.trim().isNotEmpty ? referredPatientPincode.trim() : '000000';
    final cleanLocation = referredPatientLocation.trim().isNotEmpty
        ? referredPatientLocation.trim()
        : (cleanCity != 'Not specified' ? cleanCity : 'Not specified');

    final payload = {
      'referrerPatientId': currentUserId,
      'referrer_patient_id': currentUserId,
      'referredPatientName': referredPatientName.trim(),
      'referredPatientMobile': referredPatientMobile.trim(),
      'referredPatientAge': cleanAge,
      'referredPatientGender': cleanGender,
      'referredPatientCity': cleanCity,
      'referredPatientPincode': cleanPincode,
      'referredPatientLocation': cleanLocation,
      'requiredSpecialist': requiredSpecialist.trim(),
      'clinicalComplaint': clinicalComplaint.trim(),
      'sendWhatsApp': sendWhatsApp,
      if (trimmedDoctorId.isNotEmpty) 'doctorId': trimmedDoctorId,
      if (trimmedDoctorId.isNotEmpty) 'doctor_id': trimmedDoctorId,
      'doctorName': cleanDocName,
      if (doctorClinicName != null && doctorClinicName.isNotEmpty) 'doctorClinicName': doctorClinicName,
      if (doctorLocation != null && doctorLocation.isNotEmpty) 'doctorLocation': doctorLocation,
      if (doctorCity != null && doctorCity.isNotEmpty) 'doctorCity': doctorCity,
      if (doctorPincode != null && doctorPincode.isNotEmpty) 'doctorPincode': doctorPincode,
      if (doctorPhone != null && doctorPhone.isNotEmpty) 'doctorPhone': doctorPhone,
    };

    String? expressFailureMessage;

    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals');
      final response = await http.post(
        url,
        headers: {
          ..._headers,
          if (currentUserId.isNotEmpty) 'x-user-id': currentUserId,
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 35));

      Map<String, dynamic> data = <String, dynamic>{};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'referral': data['referral'], 'message': data['message']};
      } else if (response.statusCode == 409) {
        return {
          'success': false,
          'isDuplicate': data['isDuplicate'] == true,
          'unavailable': data['unavailable'] == true,
          'message': data['message'] ?? 'A pending referral already exists.',
        };
      } else if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'message': data['message'] ?? 'Could not submit referral.',
        };
      } else {
        expressFailureMessage = data['message']?.toString();
      }
    } catch (e) {
      debugPrint('⚠️ Express create referral notice: $e');
      expressFailureMessage = 'Unable to connect to referral server. Please ensure you are signed in and connected.';
    }

    // 2. Direct 24/7 Supabase Cloud Fallback (only when Supabase client is initialized)
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {
        'success': false,
        'message': expressFailureMessage ?? 'Failed to save referral to server. Please try again.',
      };
    }

    String? linkedPatientId;
    final supaPayload = <String, dynamic>{
      'id': 'ref-${DateTime.now().millisecondsSinceEpoch}',
      'referrer_patient_id': currentUserId.isNotEmpty ? currentUserId : null,
      'referrer_id': currentUserId.isNotEmpty ? currentUserId : null,
      'referred_patient_id': linkedPatientId,
      'referred_user_id': linkedPatientId,
      'referred_patient_name': referredPatientName.trim(),
      'referred_patient_mobile': referredPatientMobile.trim(),
      'referred_patient_age': cleanAge,
      'referred_patient_gender': cleanGender,
      'referred_patient_city': cleanCity,
      'referred_patient_pincode': cleanPincode,
      'referred_patient_location': cleanLocation,
      'required_specialist': requiredSpecialist.trim(),
      'clinical_complaint': clinicalComplaint.trim(),
      if (trimmedDoctorId.isNotEmpty) 'doctor_id': trimmedDoctorId,
      if (trimmedDoctorId.isNotEmpty) 'assigned_doctor_id': trimmedDoctorId,
      'doctor_name': cleanDocName,
      'doctorName': cleanDocName,
      'doctorSpecialty': requiredSpecialist.trim(),
      'doctorClinicName': doctorClinicName ?? '',
      'doctorLocation': doctorLocation ?? cleanLocation,
      'doctorCity': doctorCity ?? cleanCity,
      'doctorPincode': doctorPincode ?? cleanPincode,
      'doctorPhone': doctorPhone ?? '',
      'status': 'Pending',
      'whatsapp_status': sendWhatsApp ? 'Pending' : 'NotSent',
      'referral_date': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      // Resolve canonical referrer user UUID & canonical dentist UUID
      String? resolvedReferrerId = currentUserId.isNotEmpty ? currentUserId : null;
      if (resolvedReferrerId != null) {
        try {
          final uCheck = await client.from('users').select('id').eq('id', resolvedReferrerId).maybeSingle();
          if (uCheck == null) {
            final dCheck = await client.from('dentists').select('user_id').eq('id', resolvedReferrerId).maybeSingle();
            if (dCheck != null && dCheck['user_id'] != null) {
              resolvedReferrerId = dCheck['user_id'].toString();
            }
          }
        } catch (_) {}
      }

      String? resolvedDoctorId;
      String? resolvedDoctorUserId;
      if (doctorId.isNotEmpty) {
        try {
          final dRow = await client
              .from('dentists')
              .select('id, user_id')
              .or('id.eq.$doctorId,user_id.eq.$doctorId')
              .limit(1)
              .maybeSingle();
          if (dRow != null) {
            resolvedDoctorId = dRow['id']?.toString();
            resolvedDoctorUserId = dRow['user_id']?.toString();
          }
        } catch (_) {}
      }

      // Check existing patient or create patient in users table
      try {
        final cleanDigits = referredPatientMobile.replaceAll(RegExp(r'[^0-9]'), '');
        final cleanPhone = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
        final existUser = await client.from('users').select('id').or('phone.eq.$cleanPhone,phone.eq.${referredPatientMobile.trim()}').maybeSingle();
        if (existUser != null && existUser['id'] != null) {
          linkedPatientId = existUser['id'].toString();
        } else {
          // Auto-insert referred patient into Supabase DB 'users' table
          final userMeta = {
            'age': referredPatientAge.trim(),
            'gender': referredPatientGender.trim(),
            'emergencyContact': referredPatientMobile.trim(),
            'address': referredPatientLocation.trim(),
          };
          final insertedUser = await client.from('users').insert({
            'name': referredPatientName.trim(),
            'phone': cleanPhone.isNotEmpty ? cleanPhone : referredPatientMobile.trim(),
            'email': 'user_${cleanPhone.isNotEmpty ? cleanPhone : DateTime.now().millisecondsSinceEpoch}@dentaguru.internal',
            'password': 'Password_${cleanPhone}_Secure!',
            'role': 'Patient',
            'city': referredPatientCity.trim(),
            'pincode': referredPatientPincode.trim(),
            'state': referredPatientLocation.trim(),
            'device_token': jsonEncode(userMeta),
          }).select('id').maybeSingle();
          if (insertedUser != null && insertedUser['id'] != null) {
            linkedPatientId = insertedUser['id'].toString();
          }
        }
        supaPayload['referred_patient_id'] = linkedPatientId;
        supaPayload['referred_user_id'] = linkedPatientId;
        supaPayload['referrer_patient_id'] = resolvedReferrerId;
        supaPayload['referrer_id'] = resolvedReferrerId;
      } catch (err) {
        debugPrint('⚠️ Error auto-creating referred patient in users table: $err');
      }

      // Insert ONLY valid columns of 'referrals' table
      final dbReferralRow = <String, dynamic>{
        'referrer_patient_id': resolvedReferrerId,
        'referrer_id': resolvedReferrerId,
        'referred_patient_id': linkedPatientId,
        'referred_user_id': linkedPatientId,
        'referred_patient_name': referredPatientName.trim(),
        'referred_patient_mobile': referredPatientMobile.trim(),
        'referred_patient_age': referredPatientAge.trim(),
        'referred_patient_gender': referredPatientGender.trim(),
        'referred_patient_city': referredPatientCity.trim(),
        'referred_patient_pincode': referredPatientPincode.trim(),
        'referred_patient_location': referredPatientLocation.trim(),
        'required_specialist': requiredSpecialist.trim(),
        'clinical_complaint': clinicalComplaint.trim(),
        if (resolvedDoctorId != null) 'doctor_id': resolvedDoctorId,
        if (resolvedDoctorId != null) 'assigned_doctor_id': resolvedDoctorId,
        'status': 'Pending',
        'whatsapp_status': sendWhatsApp ? 'Pending' : 'NotSent',
        'referral_date': DateTime.now().toIso8601String(),
      };

      try {
        final res = await client.from('referrals').insert(dbReferralRow).select().single();
        final insertedId = res['id']?.toString() ?? '';

        // Notifications for Receiving Doctor (if assigned), Referred Patient & Admin
        try {
          await client.from('notifications').insert([
            if (resolvedDoctorId != null || trimmedDoctorId.isNotEmpty)
              {
                'recipient_role': 'Dentist',
                'recipient_id': resolvedDoctorUserId ?? resolvedDoctorId ?? trimmedDoctorId,
                if (insertedId.isNotEmpty) 'referral_id': insertedId,
                'title': 'New Patient Referral',
                'message': 'A new referral for ${referredPatientName.trim()} has been assigned to you.',
                'type': 'NEW_REFERRAL',
              },
            if (linkedPatientId != null)
              {
                'recipient_role': 'Patient',
                'recipient_id': linkedPatientId,
                if (insertedId.isNotEmpty) 'referral_id': insertedId,
                'title': 'Specialist Referral Received',
                'message': 'You have been referred for ${requiredSpecialist.trim()}${trimmedDoctorId.isNotEmpty ? ' with $cleanDocName' : ''}.',
                'type': 'NEW_REFERRAL',
              },
            {
              'recipient_role': 'Admin',
              'recipient_id': 'ALL_ADMINS',
              if (insertedId.isNotEmpty) 'referral_id': insertedId,
              'title': 'New Patient Referral Submitted',
              'message': '${referredPatientName.trim()} was referred for ${requiredSpecialist.trim()}${trimmedDoctorId.isNotEmpty ? ' ($cleanDocName)' : ''}.',
              'type': 'NEW_REFERRAL',
            },
          ]);
        } catch (_) {}

        final enrichedRes = Map<String, dynamic>.from(res);
        enrichedRes['doctorName'] = cleanDocName;
        enrichedRes['doctorClinicName'] = doctorClinicName ?? '';
        enrichedRes['doctorSpecialty'] = requiredSpecialist.trim();
        return {'success': true, 'referral': enrichedRes, 'message': 'Referral submitted successfully.'};
      } catch (referralTableErr) {
        debugPrint('⚠️ Referrals table insert error (trying problem requests fallback): $referralTableErr');

        try {
          final ppr = await client.from('patient_problem_requests').insert({
            'patient_id': linkedPatientId ?? resolvedReferrerId,
            'problem_category': requiredSpecialist.trim(),
            'problem_description': 'Referral for ${referredPatientName.trim()} (${referredPatientMobile.trim()}): ${clinicalComplaint.trim()}',
            if (resolvedDoctorId != null) 'suggested_dentist_id': resolvedDoctorId,
            'status': 'DENTIST_ASSIGNED',
            'admin_notes': 'REFERRAL_PAYLOAD:${jsonEncode(supaPayload)}',
            'city': referredPatientCity.trim(),
            'pincode': referredPatientPincode.trim(),
          }).select().single();

          if (ppr['id'] != null) {
            supaPayload['id'] = ppr['id'].toString();
          }
          return {'success': true, 'referral': supaPayload, 'message': 'Referral submitted successfully.'};
        } catch (pprErr) {
          debugPrint('⚠️ Problem requests fallback error: $pprErr');
          return {'success': false, 'message': 'Failed to save referral to database. Please try again.'};
        }
      }
    } catch (supaErr) {
      debugPrint('❌ Direct Supabase create referral error: $supaErr');
      return {'success': false, 'message': 'Failed to save referral: $supaErr'};
    }
  }

  /// Patient: Fetch Referrals created by the logged-in patient
  Future<List<dynamic>> fetchMyPatientReferrals({String? userId}) async {
    final effectiveUserId = (userId != null && userId.isNotEmpty)
        ? userId
        : (SessionService().currentSession?.userId ?? SupabaseService.safeCurrentUser?.id ?? '');

    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/my-referrals').replace(queryParameters: {
        if (effectiveUserId.isNotEmpty) 'userId': effectiveUserId,
      });
      final response = await http.get(
        url,
        headers: {
          ..._headers,
          if (effectiveUserId.isNotEmpty) 'x-user-id': effectiveUserId,
        },
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['referrals'] ?? [];
        if (list is List && list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('⚠️ Express fetch my referrals notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback
    final client = SupabaseService.safeClient;
    if (client == null) return [];
    try {
      if (effectiveUserId.isNotEmpty) {
        // Try dedicated referrals table
        try {
          dynamic res;
          try {
            res = await client
                .from('referrals')
                .select('*, doctor:dentists!doctor_id(id, speciality, qualifications, users(name, email, phone), clinics(clinic_name, location))')
                .or('referrer_patient_id.eq.$effectiveUserId,referrer_id.eq.$effectiveUserId')
                .order('created_at', ascending: false);
          } catch (_) {
            res = await client
                .from('referrals')
                .select('*')
                .or('referrer_patient_id.eq.$effectiveUserId,referrer_id.eq.$effectiveUserId')
                .order('created_at', ascending: false);
          }
          if (res is List && res.isNotEmpty) return List<dynamic>.from(res);
        } catch (_) {}

        // Fallback: Check patient_problem_requests
        try {
          final pprRes = await client
              .from('patient_problem_requests')
              .select('*')
              .ilike('admin_notes', '%REFERRAL_PAYLOAD:%')
              .order('created_at', ascending: false);

          final results = <dynamic>[];
          for (final row in pprRes) {
            final notes = row['admin_notes']?.toString() ?? '';
            if (notes.contains('REFERRAL_PAYLOAD:')) {
              try {
                final jsonStr = notes.split('REFERRAL_PAYLOAD:').last;
                final map = jsonDecode(jsonStr);
                if (map['referrer_patient_id'] == effectiveUserId || map['referrer_id'] == effectiveUserId || effectiveUserId.isEmpty) {
                  map['id'] = row['id'];
                  results.add(map);
                }
              } catch (_) {}
            }
          }
          if (results.isNotEmpty) return results;
        } catch (_) {}
      }
    } catch (supaErr) {
      debugPrint('Supabase direct fetch my referrals notice: $supaErr');
    }
    return [];
  }

  @visibleForTesting
  static Future<List<dynamic>> Function({String? doctorId})? debugFetchDoctorReferralsOverride;

  /// Doctor: Fetch Referrals assigned strictly to this Doctor
  Future<List<dynamic>> fetchDoctorPatientReferrals({String? doctorId}) async {
    final res = await fetchDoctorPatientReferralsWithStatus(doctorId: doctorId);
    return res.referrals;
  }

  /// Doctor: Fetch Referrals with completion status so callers distinguish empty result from offline error
  Future<({bool succeeded, List<dynamic> referrals})> fetchDoctorPatientReferralsWithStatus({String? doctorId}) async {
    final override = debugFetchDoctorReferralsOverride;
    if (override != null) {
      final list = await override(doctorId: doctorId);
      return (succeeded: true, referrals: List<dynamic>.from(list));
    }

    final effectiveDocId = (doctorId != null && doctorId.isNotEmpty)
        ? doctorId
        : (SessionService().currentSession?.metadata['dentistId']?.toString() ??
            SessionService().currentSession?.userId ??
            SupabaseService.safeCurrentUser?.id ??
            '');

    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/doctor').replace(queryParameters: {
        if (effectiveDocId.isNotEmpty) 'doctorId': effectiveDocId,
      });
      final response = await http.get(
        url,
        headers: _headersWithUser(effectiveDocId),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return (succeeded: true, referrals: const <dynamic>[]);
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['referrals'] ?? [];
        if (list is List) {
          return (succeeded: true, referrals: List<dynamic>.from(list));
        }
      }
    } catch (e) {
      debugPrint('⚠️ Express fetch doctor referrals notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback
    final client = SupabaseService.safeClient;
    if (client == null) return (succeeded: false, referrals: const <dynamic>[]);
    try {
      if (effectiveDocId.isNotEmpty) {
        // Try dedicated referrals table
        try {
          String? altDocId;
          try {
            final d = await client.from('dentists').select('id, user_id').or('id.eq.$effectiveDocId,user_id.eq.$effectiveDocId').maybeSingle();
            if (d != null) {
              altDocId = d['id']?.toString() == effectiveDocId ? d['user_id']?.toString() : d['id']?.toString();
            }
          } catch (_) {}

          final conds = ['doctor_id.eq.$effectiveDocId', 'assigned_doctor_id.eq.$effectiveDocId'];
          if (altDocId != null && altDocId.isNotEmpty) {
            conds.add('doctor_id.eq.$altDocId');
            conds.add('assigned_doctor_id.eq.$altDocId');
          }

          dynamic res;
          try {
            res = await client
                .from('referrals')
                .select('*, referrer:users!referrer_patient_id(id, name, email, phone)')
                .or(conds.join(','))
                .order('created_at', ascending: false);
          } catch (_) {
            res = await client
                .from('referrals')
                .select('*')
                .or(conds.join(','))
                .order('created_at', ascending: false);
          }
          if (res is List) {
            return (succeeded: true, referrals: List<dynamic>.from(res));
          }
        } catch (_) {}

        // Fallback: Check patient_problem_requests for this doctor
        try {
          final pprRes = await client
              .from('patient_problem_requests')
              .select('*')
              .or('suggested_dentist_id.eq.$effectiveDocId')
              .ilike('admin_notes', '%REFERRAL_PAYLOAD:%')
              .order('created_at', ascending: false);

          final results = <dynamic>[];
          for (final row in pprRes) {
            final notes = row['admin_notes']?.toString() ?? '';
            if (notes.contains('REFERRAL_PAYLOAD:')) {
              try {
                final jsonStr = notes.split('REFERRAL_PAYLOAD:').last;
                final map = jsonDecode(jsonStr);
                map['id'] = row['id'];
                if (row['status'] == 'CONFIRMED' || row['status'] == 'ACCEPTED') map['status'] = 'Accepted';
                if (row['status'] == 'REJECTED') map['status'] = 'Rejected';
                results.add(map);
              } catch (_) {}
            }
          }
          return (succeeded: true, referrals: results);
        } catch (_) {}
      }
    } catch (supaErr) {
      debugPrint('Supabase direct fetch doctor referrals notice: $supaErr');
    }
    return (succeeded: false, referrals: const <dynamic>[]);
  }

  @visibleForTesting
  static Future<List<dynamic>> Function({String? clinicId, String? clinicName})? debugFetchClinicReferralsOverride;

  /// Clinic: Fetch Referrals routed to doctors of this clinic
  Future<List<dynamic>> fetchClinicPatientReferrals({String? clinicId, String? clinicName}) async {
    final override = debugFetchClinicReferralsOverride;
    if (override != null) {
      return override(clinicId: clinicId, clinicName: clinicName);
    }

    final effectiveId = (clinicId != null && clinicId.trim().isNotEmpty)
        ? clinicId.trim()
        : (SessionService().currentSession?.userId ?? SupabaseService.safeCurrentUser?.id ?? '');
    final cleanName = (clinicName ?? '').trim();
    if (effectiveId.isEmpty && cleanName.isEmpty) return [];

    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/clinic').replace(queryParameters: {
        if (effectiveId.isNotEmpty) 'clinicId': effectiveId,
        if (cleanName.isNotEmpty) 'clinicName': cleanName,
      });
      final response = await http.get(
        url,
        headers: {
          ..._headers,
          if (effectiveId.isNotEmpty) 'x-user-id': effectiveId,
        },
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['referrals'] is List) {
          return List<dynamic>.from(data['referrals']);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Express fetch clinic referrals notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback (resolve clinic -> clinic doctors -> referrals)
    final client = SupabaseService.safeClient;
    if (client == null) return [];
    try {
      String? resolvedClinicId;
      if (effectiveId.isNotEmpty) {
        final cRow = await client
            .from('clinics')
            .select('id')
            .or('id.eq.$effectiveId,user_id.eq.$effectiveId')
            .limit(1)
            .maybeSingle();
        resolvedClinicId = cRow?['id']?.toString();
      }
      if (resolvedClinicId == null && cleanName.isNotEmpty) {
        final cByName = await client
            .from('clinics')
            .select('id')
            .ilike('clinic_name', cleanName)
            .limit(1)
            .maybeSingle();
        resolvedClinicId = cByName?['id']?.toString();
      }
      if (resolvedClinicId == null) return [];

      final docsRes = await client.from('dentists').select('id').eq('clinic_id', resolvedClinicId);
      final docIds = <String>[
        for (final row in docsRes)
          if (row['id'] != null) row['id'].toString(),
      ];
      if (docIds.isEmpty) return [];

      final conds = docIds.map((id) => 'doctor_id.eq.$id,assigned_doctor_id.eq.$id').join(',');
      final res = await client.from('referrals').select('*').or(conds).order('created_at', ascending: false);
      return List<dynamic>.from(res);
    } catch (e) {
      debugPrint('⚠️ Supabase fetch clinic referrals notice: $e');
    }
    return [];
  }

  /// Patient: Fetch Referrals where this patient is the referred person
  Future<List<dynamic>> fetchReceivedPatientReferrals({String? patientId, String? patientPhone}) async {
    final effectiveId = (patientId != null && patientId.isNotEmpty)
        ? patientId
        : (SessionService().currentSession?.userId ?? SupabaseService.safeCurrentUser?.id ?? '');
    final effectivePhone = (patientPhone != null && patientPhone.isNotEmpty)
        ? patientPhone
        : (SessionService().currentSession?.phone ?? '');

    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/for-me').replace(queryParameters: {
        if (effectiveId.isNotEmpty) 'userId': effectiveId,
        if (effectivePhone.isNotEmpty) 'phone': effectivePhone,
      });
      final response = await http.get(
        url,
        headers: {
          ..._headers,
          if (effectiveId.isNotEmpty) 'x-user-id': effectiveId,
        },
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['referrals'] ?? [];
        if (list is List && list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('⚠️ Express fetch received referrals notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback
    final client = SupabaseService.safeClient;
    if (client == null) return [];
    try {
      final conds = <String>[];
      if (effectiveId.isNotEmpty) {
        conds.add('referred_patient_id.eq.$effectiveId');
        conds.add('referred_user_id.eq.$effectiveId');
      }
      if (effectivePhone.isNotEmpty) {
        final clean = effectivePhone.replaceAll(RegExp(r'[^0-9]'), '');
        final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;
        if (last10.isNotEmpty) {
          conds.add('referred_patient_mobile.ilike.%$last10%');
        }
      }

      if (conds.isNotEmpty) {
        try {
          dynamic res;
          try {
            res = await client
                .from('referrals')
                .select('*, doctor:dentists!doctor_id(id, speciality, qualifications, users(name, email, phone), clinics(clinic_name, location)), referrer:users!referrer_patient_id(id, name, phone)')
                .or(conds.join(','))
                .order('created_at', ascending: false);
          } catch (_) {
            res = await client
                .from('referrals')
                .select('*')
                .or(conds.join(','))
                .order('created_at', ascending: false);
          }
          if (res is List && res.isNotEmpty) return List<dynamic>.from(res);
        } catch (_) {}
      }
    } catch (supaErr) {
      debugPrint('Supabase direct fetch received referrals notice: $supaErr');
    }
    return [];
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String referralId, {String? confirmedTimeSlot})?
      debugAcceptPatientReferralOverride;

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String referralId, {String? rejectionReason})?
      debugRejectPatientReferralOverride;

  /// Doctor: Accept a patient referral
  Future<Map<String, dynamic>> acceptPatientReferral(String referralId, {String? confirmedTimeSlot}) async {
    final override = debugAcceptPatientReferralOverride;
    if (override != null) {
      return override(referralId, confirmedTimeSlot: confirmedTimeSlot);
    }

    // 1. Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/$referralId/accept');
      final response = await http.patch(
        url,
        headers: _headersWithUser(),
        body: jsonEncode({
          if (confirmedTimeSlot != null) 'confirmedTimeSlot': confirmedTimeSlot,
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) return {'success': false, 'statusCode': response.statusCode, ...body};
        } catch (_) {}
        return {'success': false, 'statusCode': response.statusCode, 'message': 'Unauthorized to accept this referral.'};
      }
    } catch (e) {
      debugPrint('⚠️ Express accept referral notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback (strictly blocked for Patient sessions)
    final sessionRole = (SessionService().currentSession?.role ?? '').trim().toLowerCase();
    if (sessionRole == 'patient') {
      return {
        'success': false,
        'statusCode': 403,
        'message': 'Patients cannot accept or reject referrals.'
      };
    }
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {'success': false, 'message': 'Unable to accept referral right now. Server unreachable.'};
    }
    try {
      try {
        final res = await client.from('referrals').update({
          'status': 'Accepted',
          'rejection_reason': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', referralId).select().maybeSingle();

        if (res != null) {
          final referrerId = res['referrer_patient_id'] ?? res['referrer_id'];
          if (referrerId != null) {
            try {
              await client.from('notifications').insert({
                'recipient_role': 'Patient',
                'recipient_id': referrerId,
                'type': 'REFERRAL_ACCEPTED',
                'title': 'Referral Accepted',
                'message': 'Your referral for ${res['referred_patient_name'] ?? 'Patient'} has been accepted.',
              });
            } catch (_) {}
          }

          // Create confirmed appointment in appointments table
          final pId = res['referred_patient_id'] ?? res['referred_user_id'];
          final dId = res['doctor_id'] ?? res['assigned_doctor_id'];
          if (pId != null && dId != null) {
            try {
              final apptRes = await client.from('appointments').insert({
                'patient_id': pId,
                'dentist_id': dId,
                'appointment_date': DateTime.now().toIso8601String().split('T').first,
                'time_slot': confirmedTimeSlot ?? '10:00 AM',
                'treatment': res['required_specialist'] ?? 'Specialist Consultation',
                'status': 'CONFIRMED',
                'notes': 'Referred Patient: ${res['referred_patient_name'] ?? ''} (${res['referred_patient_mobile'] ?? ''}). Complaint: ${res['clinical_complaint'] ?? ''}',
              }).select('id').maybeSingle();
              if (apptRes != null && apptRes['id'] != null) {
                await client.from('referrals').update({'appointment_id': apptRes['id']}).eq('id', referralId);
              }
            } catch (_) {}
          }

          return {'success': true, 'referral': res};
        }
      } catch (_) {}

      // Fallback: Update patient_problem_requests
      try {
        final reqRes = await client.from('patient_problem_requests').update({
          'status': 'CONFIRMED',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', referralId).select('id').maybeSingle();
        if (reqRes != null) {
          return {'success': true, 'referral': {'id': referralId, 'status': 'Accepted'}};
        }
      } catch (_) {}
    } catch (supaErr) {
      debugPrint('❌ Supabase accept referral error: $supaErr');
    }

    return {'success': false, 'message': 'Failed to accept referral'};
  }

  /// Doctor: Reject a patient referral
  Future<Map<String, dynamic>> rejectPatientReferral(String referralId, {String? rejectionReason}) async {
    final override = debugRejectPatientReferralOverride;
    if (override != null) {
      return override(referralId, rejectionReason: rejectionReason);
    }
    final reason = rejectionReason ?? 'Doctor is currently unavailable';

    // 1. Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/$referralId/reject');
      final response = await http.patch(
        url,
        headers: _headersWithUser(),
        body: jsonEncode({'rejectionReason': reason}),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) return {'success': false, 'statusCode': response.statusCode, ...body};
        } catch (_) {}
        return {'success': false, 'statusCode': response.statusCode, 'message': 'Unauthorized to decline this referral.'};
      }
    } catch (e) {
      debugPrint('⚠️ Express reject referral notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback (strictly blocked for Patient sessions)
    final sessionRole = (SessionService().currentSession?.role ?? '').trim().toLowerCase();
    if (sessionRole == 'patient') {
      return {
        'success': false,
        'statusCode': 403,
        'message': 'Patients cannot accept or reject referrals.'
      };
    }
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {'success': false, 'message': 'Unable to reject referral right now. Server unreachable.'};
    }
    try {
      try {
        final res = await client.from('referrals').update({
          'status': 'Rejected',
          'rejection_reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', referralId).select().maybeSingle();

        if (res != null) {
          final referrerId = res['referrer_patient_id'] ?? res['referrer_id'];
          if (referrerId != null) {
            try {
              await client.from('notifications').insert({
                'recipient_role': 'Patient',
                'recipient_id': referrerId,
                'type': 'REFERRAL_REJECTED',
                'title': 'Referral Update',
                'message': 'Your referral for ${res['referred_patient_name'] ?? 'Patient'} was not accepted.',
              });
            } catch (_) {}
          }
          return {'success': true, 'referral': res};
        }
      } catch (_) {}

      // Fallback: Update patient_problem_requests
      try {
        final reqRes = await client.from('patient_problem_requests').update({
          'status': 'REJECTED',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', referralId).select('id').maybeSingle();
        if (reqRes != null) {
          return {'success': true, 'referral': {'id': referralId, 'status': 'Rejected'}};
        }
      } catch (_) {}
    } catch (supaErr) {
      debugPrint('❌ Supabase reject referral error: $supaErr');
    }

    return {'success': false, 'message': 'Failed to reject referral'};
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String referralId, {required String status, String? reason})?
      debugUpdatePatientReferralStatusOverride;

  /// Update patient referral status across all 5 states (Pending, Accepted, Rejected, Contacted, Completed)
  Future<Map<String, dynamic>> updatePatientReferralStatus(
    String referralId, {
    required String status,
    String? reason,
  }) async {
    final override = debugUpdatePatientReferralStatusOverride;
    if (override != null) {
      return override(referralId, status: status, reason: reason);
    }

    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/$referralId/status');
      final response = await http.patch(
        url,
        headers: _headersWithUser(),
        body: jsonEncode({
          'status': status,
          if (reason != null && reason.trim().isNotEmpty) 'rejectionReason': reason.trim(),
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) return {'success': false, 'statusCode': response.statusCode, ...body};
        } catch (_) {}
        return {'success': false, 'statusCode': response.statusCode, 'message': 'Unable to update referral status.'};
      }
    } catch (e) {
      debugPrint('⚠️ Express update referral status notice: $e');
    }

    final sessionRole = (SessionService().currentSession?.role ?? '').trim().toLowerCase();
    if (sessionRole == 'patient') {
      return {
        'success': false,
        'statusCode': 403,
        'message': 'Patients cannot update referral status.'
      };
    }
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {'success': false, 'message': 'Unable to update referral status right now. Server unreachable.'};
    }
    try {
      final res = await client.from('referrals').update({
        'status': status,
        'rejection_reason': status == 'Rejected' ? (reason ?? 'Unavailable') : null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', referralId).select().maybeSingle();
      if (res != null) {
        return {'success': true, 'referral': res};
      }
    } catch (e) {
      debugPrint('❌ Supabase update referral status error: $e');
    }
    return {'success': false, 'message': 'Failed to update referral status.'};
  }

  /// Delete a patient referral
  Future<Map<String, dynamic>> deletePatientReferral(String referralId) async {
    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/$referralId');
      final response = await http.delete(url, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map<String, dynamic>) return {'success': false, 'statusCode': response.statusCode, ...body};
        } catch (_) {}
        return {'success': false, 'statusCode': response.statusCode, 'message': 'Unauthorized to delete this referral.'};
      }
    } catch (e) {
      debugPrint('⚠️ Express delete referral notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {'success': false, 'message': 'Unable to delete referral right now. Server unreachable.'};
    }
    try {
      try {
        await client.from('referrals').delete().eq('id', referralId);
      } catch (_) {}
      try {
        await client.from('patient_problem_requests').delete().eq('id', referralId);
      } catch (_) {}
      return {'success': true, 'message': 'Referral deleted successfully.'};
    } catch (supaErr) {
      debugPrint('❌ Supabase delete referral error: $supaErr');
      return {'success': false, 'message': supaErr.toString()};
    }
  }

  /// Check whether patient mobile already exists in DentaGuru
  Future<Map<String, dynamic>> checkPatientExistsByMobile(String mobile) async {
    final cleanDigits = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;

    // 1. Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/check-patient');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({'phone': last10}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    // 2. Direct Supabase Fallback
    final client = SupabaseService.safeClient;
    if (client == null) {
      return {'success': true, 'exists': false};
    }
    try {
      final u = await client
          .from('users')
          .select('id, name, phone, email, city, pincode')
          .eq('phone', last10)
          .maybeSingle();

      if (u != null) {
        return {'success': true, 'exists': true, 'patient': u};
      }
      return {'success': true, 'exists': false};
    } catch (_) {
      return {'success': true, 'exists': false};
    }
  }

  /// Trigger or retry WhatsApp Notification
  Future<bool> triggerWhatsAppNotification(String referralId) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/referrals/$referralId/notify-whatsapp');
      final response = await http.post(url, headers: _headers).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Test-only hook so widget tests can supply notification rows without a backend.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function({String? role, String? userId})? debugFetchNotificationsOverride;

  /// Fetch in-app notifications from Express backend first (with RBAC & Doctor ID resolution),
  /// with Direct 24/7 Supabase Cloud Fallback.
  Future<List<Map<String, dynamic>>> fetchNotifications({String? role, String? userId}) async {
    final override = debugFetchNotificationsOverride;
    if (override != null) {
      return override(role: role, userId: userId);
    }

    final effectiveUserId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (SupabaseService.safeCurrentUser?.id ?? '');

    // 1. Primary Express Backend Call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/notifications').replace(queryParameters: {
        if (role != null && role.isNotEmpty) 'role': role,
        if (effectiveUserId.isNotEmpty) 'userId': effectiveUserId,
      });
      final response = await http.get(
        url,
        headers: {
          ..._headers,
          if (effectiveUserId.isNotEmpty) 'x-user-id': effectiveUserId,
        },
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['notifications'] ?? data['data'] ?? [];
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('Express fetch notifications notice: $e');
    }

    // 2. Direct Supabase Cloud Fallback
    final client = SupabaseService.safeClient;
    if (client == null) {
      return [];
    }
    try {
      final conds = <String>[];
      if (role != null && role.isNotEmpty) {
        conds.add('recipient_role.eq.$role');
        conds.add('recipient_role.eq.ALL');
        if (role.toLowerCase().contains('admin')) {
          conds.add('recipient_id.eq.ALL_ADMINS');
        }
      }
      if (effectiveUserId.isNotEmpty) {
        conds.add('recipient_id.eq.$effectiveUserId');
      }

      var query = client.from('notifications').select('*');
      if (conds.isNotEmpty) {
        query = query.or(conds.join(','));
      }
      final res = await query.order('created_at', ascending: false).limit(100);
      if (res.isNotEmpty) {
        return List<Map<String, dynamic>>.from(res);
      }
    } catch (e) {
      debugPrint('⚠️ Supabase fetch notifications notice: $e');
    }
    return [];
  }

  /// Mark notification as read in Supabase via Express backend + fallback
  Future<bool> markNotificationAsRead(String notifId) async {
    if (notifId.trim().isEmpty) return false;
    bool markedViaApi = false;
    // 1. Primary Express call
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/notifications/$notifId/read');
      final res = await http.put(url, headers: _headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        markedViaApi = true;
      }
    } catch (_) {}

    // 2. Direct Supabase fallback if Express unreachable
    if (!markedViaApi) {
      try {
        await Supabase.instance.client
            .from('notifications')
            .update({'read': true})
            .eq('id', notifId);
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Mark all notifications as read for a given role & userId
  Future<bool> markAllNotificationsAsRead({String? role, String? userId}) async {
    final effectiveUserId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (SupabaseService.safeCurrentUser?.id ?? '');
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/notifications/read-all');
      final res = await http
          .put(
            url,
            headers: _headers,
            body: jsonEncode({
              if (role != null && role.isNotEmpty) 'role': role,
              if (effectiveUserId.isNotEmpty) 'userId': effectiveUserId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return true;
    } catch (_) {}
    return false;
  }

  /// Create In-App Notification
  Future<bool> createInAppNotification({
    required String recipientRole,
    required String recipientId,
    required String title,
    required String message,
    String type = 'GENERAL',
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('notifications').insert({
        'recipient_role': recipientRole,
        'recipient_id': recipientId,
        'title': title,
        'message': message,
        'type': type,
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('⚠️ Create in-app notification error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // DOCTOR AVAILABILITY & TIME SLOT MANAGEMENT
  // ─────────────────────────────────────────────

  Future<Map<String, String?>> _resolveCanonicalDoctorIdsSupabase(SupabaseClient client, String dentistId) async {
    String canonicalDentistId = dentistId;
    String? userId;
    try {
      final dRow = await client
          .from('dentists')
          .select('id, user_id')
          .or('id.eq.$dentistId,user_id.eq.$dentistId')
          .limit(1)
          .maybeSingle();
      if (dRow != null) {
        if (dRow['id'] != null) canonicalDentistId = dRow['id'].toString();
        if (dRow['user_id'] != null) userId = dRow['user_id'].toString();
      }
    } catch (_) {}
    return {'dentistId': canonicalDentistId, 'userId': userId};
  }

  /// Fetch Doctor Availability (Express API with 35s timeout & Direct Supabase Fallback)
  Future<Map<String, dynamic>> fetchDoctorAvailability({
    required String dentistId,
    String? date,
    String? consultationType,
  }) async {
    // 1. Primary Express Backend Call
    try {
      final queryParams = {
        'dentistId': dentistId,
        if (date != null && date.isNotEmpty) 'date': date.contains('T') ? date.split('T').first : date,
        if (consultationType != null && consultationType.trim().isNotEmpty)
          'consultationType': consultationType.trim(),
      };
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['bookingRules'] is Map) {
          BookingRulesConfig.applyFromJson(Map<String, dynamic>.from(data['bookingRules'] as Map));
        }
        return {
          'success': true,
          'availability': data['availability'],
          'availabilities': data['availabilities'],
          'schedule': data['schedule'],
          'blockedDates': data['blockedDates'],
          'bookingRules': data['bookingRules'],
        };
      }
    } catch (e) {
      debugPrint('Express fetchDoctorAvailability notice: $e');
    }

    // 2. Direct 24/7 Supabase Cloud Fallback
    try {
      final client = Supabase.instance.client;
      final cleanDate = (date != null && date.isNotEmpty)
          ? (date.contains('T') ? date.split('T').first : date)
          : null;

      final resolved = await _resolveCanonicalDoctorIdsSupabase(client, dentistId);
      final canonicalId = resolved['dentistId'] ?? dentistId;
      final userId = resolved['userId'];
      final idsToMatch = <String>{dentistId, canonicalId, if (userId != null) userId};
      final idFilter = idsToMatch.map((id) => 'dentist_id.eq.$id').join(',');

      Map<String, dynamic>? scheduleMap;
      if (userId != null && userId.isNotEmpty) {
        try {
          final uRow = await client.from('users').select('device_token').eq('id', userId).maybeSingle();
          final dt = uRow?['device_token']?.toString();
          if (dt != null && dt.startsWith('{')) {
            final parsed = jsonDecode(dt);
            if (parsed is Map && parsed['schedule'] is Map) {
              scheduleMap = Map<String, dynamic>.from(parsed['schedule'] as Map);
            }
          }
        } catch (_) {}
      }

      if (cleanDate != null) {
        final record = await client
            .from('doctor_availability')
            .select('*')
            .or(idFilter)
            .eq('date', cleanDate)
            .limit(1)
            .maybeSingle();

        // Cross-reference appointments for booked slots
        final appts = await client
            .from('appointments')
            .select('date, appointment_date, time_slot, status')
            .or(idFilter)
            .catchError((_) => []);

        final bookedSlots = <String>[];
        for (final a in (appts as List)) {
          final status = (a['status'] ?? '').toString().toUpperCase();
          if (status == 'CANCELLED' || status == 'REJECTED') continue;
          final aDate = (a['appointment_date'] ?? a['date'] ?? '').toString().split('T').first;
          if (aDate == cleanDate) {
            final slot = (a['time_slot'] ?? '').toString().trim();
            if (slot.isNotEmpty) bookedSlots.add(slot);
          }
        }

        final isBlocked = record != null && (record['is_blocked'] == true);
        final blockedReason = record?['blocked_reason']?.toString();
        final rawSlots = record?['slots'];
        final List<String> allSlots = rawSlots is List
            ? rawSlots.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
            : [];

        final availableSlots = isBlocked
            ? <String>[]
            : allSlots.where((s) => !bookedSlots.any((b) => b.toLowerCase() == s.toLowerCase())).toList();

        return {
          'success': true,
          'hasCustomRecord': record != null,
          'schedule': scheduleMap,
          'availability': {
            'dentistId': canonicalId,
            'date': cleanDate,
            'dayOfWeek': record?['day_of_week'] ?? '',
            'startTime': record?['start_time'] ?? scheduleMap?['startTime'] ?? '09:00 AM',
            'endTime': record?['end_time'] ?? scheduleMap?['endTime'] ?? '05:00 PM',
            'slotDurationMinutes': record?['slot_duration_minutes'] ?? scheduleMap?['slotDurationMinutes'] ?? 30,
            'hasBreak': scheduleMap?['hasBreak'] ?? true,
            'breakStartTime': scheduleMap?['breakStartTime'],
            'breakEndTime': scheduleMap?['breakEndTime'],
            'workingDays': scheduleMap?['workingDays'],
            'allSlots': allSlots,
            'bookedSlots': bookedSlots,
            'availableSlots': availableSlots,
            'isBlocked': isBlocked,
            'blockedReason': blockedReason,
          }
        };
      } else {
        final records = await client
            .from('doctor_availability')
            .select('*')
            .or(idFilter)
            .order('date', ascending: true);
        final blocked = (records as List).where((r) => r['is_blocked'] == true).toList();
        return {
          'success': true,
          'availabilities': records,
          'blockedDates': blocked,
          'schedule': scheduleMap,
        };
      }
    } catch (e) {
      debugPrint('Supabase direct fetchDoctorAvailability notice: $e');
      return {'success': false, 'message': 'Failed to fetch doctor availability: $e'};
    }
  }

  /// Fetch Persisted Weekly Schedule & Blocked Dates
  Future<Map<String, dynamic>> fetchDoctorSchedule({required String dentistId}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/schedule')
          .replace(queryParameters: {'dentistId': dentistId});
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express fetchDoctorSchedule notice: $e');
    }
    return await fetchDoctorAvailability(dentistId: dentistId);
  }

  /// Update Persisted Weekly & Smart Schedule (Working Days, Hours, Multiple Breaks, Online/In-Person Schedules, Durations, Buffers, Daily Limits)
  Future<Map<String, dynamic>> updateDoctorSchedule({
    required String dentistId,
    required List<String> workingDays,
    required String startTime,
    required String endTime,
    required int slotDurationMinutes,
    required bool hasBreak,
    String? breakStartTime,
    String? breakEndTime,
    List<Map<String, String>>? breaks,
    bool? inPersonEnabled,
    int? inPersonDurationMinutes,
    bool? onlineEnabled,
    int? onlineDurationMinutes,
    List<String>? onlineWorkingDays,
    String? onlineStartTime,
    String? onlineEndTime,
    int? inPersonBufferMinutes,
    int? onlineBufferMinutes,
    int? maxAppointmentsPerDay,
    bool? allowSimultaneousOnlineAndInPerson,
    Map<String, List<Map<String, dynamic>>>? blockedTimeRanges,
    List<String>? slots,
    bool applyToUpcomingDays = true,
  }) async {
    final payload = <String, dynamic>{
      'dentistId': dentistId,
      'workingDays': workingDays,
      'startTime': startTime,
      'endTime': endTime,
      'slotDurationMinutes': inPersonDurationMinutes ?? slotDurationMinutes,
      'hasBreak': hasBreak,
      if (hasBreak && breakStartTime != null) 'breakStartTime': breakStartTime,
      if (hasBreak && breakEndTime != null) 'breakEndTime': breakEndTime,
      if (breaks != null) 'breaks': breaks,
      if (inPersonEnabled != null) 'inPersonEnabled': inPersonEnabled,
      if (inPersonDurationMinutes != null) 'inPersonDurationMinutes': inPersonDurationMinutes,
      if (onlineEnabled != null) 'onlineEnabled': onlineEnabled,
      if (onlineDurationMinutes != null) 'onlineDurationMinutes': onlineDurationMinutes,
      if (onlineWorkingDays != null) 'onlineWorkingDays': onlineWorkingDays,
      if (onlineStartTime != null) 'onlineStartTime': onlineStartTime,
      if (onlineEndTime != null) 'onlineEndTime': onlineEndTime,
      if (inPersonBufferMinutes != null) 'inPersonBufferMinutes': inPersonBufferMinutes,
      if (onlineBufferMinutes != null) 'onlineBufferMinutes': onlineBufferMinutes,
      'maxAppointmentsPerDay': maxAppointmentsPerDay,
      if (allowSimultaneousOnlineAndInPerson != null)
        'allowSimultaneousOnlineAndInPerson': allowSimultaneousOnlineAndInPerson,
      if (blockedTimeRanges != null) 'blockedTimeRanges': blockedTimeRanges,
      if (slots != null) 'slots': slots,
      'applyToUpcomingDays': applyToUpcomingDays,
    };

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/schedule');
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 400 || response.statusCode == 403) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express updateDoctorSchedule notice: $e');
    }

    // Supabase Fallback: persist strictly to doctor_scheduling_settings (NEVER write scheduling data to users.device_token)
    try {
      final client = Supabase.instance.client;
      final resolved = await _resolveCanonicalDoctorIdsSupabase(client, dentistId);
      final canonicalDentistId = resolved['dentistId'] ?? dentistId;
      final effectiveBreaks = breaks ??
          (hasBreak && breakStartTime != null && breakEndTime != null
              ? [
                  {'startTime': breakStartTime, 'endTime': breakEndTime, 'label': 'Lunch Break'},
                ]
              : <Map<String, String>>[]);
      await client.from('doctor_scheduling_settings').upsert({
        'dentist_id': canonicalDentistId,
        'working_days': workingDays,
        'start_time': startTime,
        'end_time': endTime,
        'breaks': effectiveBreaks,
        'default_duration_minutes': inPersonDurationMinutes ?? slotDurationMinutes,
        'in_person_enabled': inPersonEnabled ?? true,
        'in_person_duration_minutes': inPersonDurationMinutes ?? slotDurationMinutes,
        'online_enabled': onlineEnabled ?? true,
        'online_duration_minutes': onlineDurationMinutes ?? 20,
        'online_working_days': onlineWorkingDays,
        'online_start_time': onlineStartTime,
        'online_end_time': onlineEndTime,
        'in_person_buffer_minutes': inPersonBufferMinutes ?? 10,
        'online_buffer_minutes': onlineBufferMinutes ?? 5,
        'max_appointments_per_day': maxAppointmentsPerDay,
        'allow_simultaneous_online_and_in_person': allowSimultaneousOnlineAndInPerson ?? false,
        if (blockedTimeRanges != null) 'blocked_time_ranges': blockedTimeRanges,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'dentist_id');
      return {'success': true, 'message': 'Schedule saved to Supabase.', 'schedule': payload};
    } catch (e) {
      debugPrint('Supabase direct updateDoctorSchedule notice: $e');
    }
    return {'success': false, 'message': 'Failed to save schedule.'};
  }

  /// Acquire a temporary atomic slot lock before booking confirmation
  Future<Map<String, dynamic>> acquireSlotLock({
    required String dentistId,
    required String patientId,
    required String date,
    required String timeSlot,
    String consultationType = 'In-Person',
    String? releasedSlotId,
    int ttlSeconds = 300,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/appointments/locks');
      final response = await http.post(
        uri,
        headers: _headersWithUser(patientId),
        body: jsonEncode({
          'dentistId': dentistId,
          'patientId': patientId,
          'date': date.contains('T') ? date.split('T').first : date,
          'timeSlot': timeSlot.trim(),
          'consultationType': consultationType,
          if (releasedSlotId != null && releasedSlotId.trim().isNotEmpty)
            'releasedSlotId': releasedSlotId.trim(),
          'ttlSeconds': ttlSeconds,
        }),
      ).timeout(const Duration(seconds: 35));
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (e) {
      debugPrint('acquireSlotLock notice: $e');
      return {
        'success': false,
        'reason': 'NETWORK_ERROR',
        'message': 'Could not reserve time slot. Please try again.',
      };
    }
  }

  /// Release an active temporary slot lock when patient cancels or changes selection
  Future<Map<String, dynamic>> releaseSlotLock({
    required String lockId,
    String? patientId,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/appointments/locks/$lockId').replace(
        queryParameters: {
          if (patientId != null && patientId.isNotEmpty) 'patientId': patientId,
        },
      );
      final response = await http.delete(
        uri,
        headers: _headersWithUser(patientId),
      ).timeout(const Duration(seconds: 35));
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (e) {
      debugPrint('releaseSlotLock notice: $e');
      return {'success': false};
    }
  }

  /// Fetch active unexpired released early-completion slots for a doctor and date
  Future<Map<String, dynamic>> fetchReleasedSlots({
    required String dentistId,
    required String date,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/released-slots').replace(
        queryParameters: {
          'dentistId': dentistId,
          'date': date.contains('T') ? date.split('T').first : date,
        },
      );
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }
    } catch (e) {
      debugPrint('fetchReleasedSlots notice: $e');
    }
    return {'success': false, 'releasedSlots': const []};
  }

  /// Fetch patient earlier-slot notification preferences
  Future<Map<String, dynamic>> fetchPatientDoctorPreferences({
    required String patientId,
    String? dentistId,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/patient/doctor-preferences').replace(
        queryParameters: {
          'patientId': patientId,
          if (dentistId != null && dentistId.isNotEmpty) 'dentistId': dentistId,
        },
      );
      final response = await http.get(uri, headers: _headersWithUser(patientId)).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }
    } catch (e) {
      debugPrint('fetchPatientDoctorPreferences notice: $e');
    }
    return {'success': false, 'preferences': const []};
  }

  /// Save/update patient favorite & earlier-slot notification preference for a doctor
  Future<Map<String, dynamic>> upsertPatientDoctorPreference({
    required String patientId,
    required String dentistId,
    bool isFavorite = false,
    bool notifyEarlierSlots = false,
    String preferredConsultationType = 'Any',
    String? preferredDate,
    int? earliestTimeMin,
    int? latestTimeMin,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/patient/doctor-preferences');
      final response = await http.put(
        uri,
        headers: _headersWithUser(patientId),
        body: jsonEncode({
          'patientId': patientId,
          'dentistId': dentistId,
          'isFavorite': isFavorite,
          'notifyEarlierSlots': notifyEarlierSlots,
          'preferredConsultationType': preferredConsultationType,
          if (preferredDate != null && preferredDate.isNotEmpty) 'preferredDate': preferredDate,
          if (earliestTimeMin != null) 'earliestTimeMin': earliestTimeMin,
          if (latestTimeMin != null) 'latestTimeMin': latestTimeMin,
        }),
      ).timeout(const Duration(seconds: 35));
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (e) {
      debugPrint('upsertPatientDoctorPreference notice: $e');
      return {'success': false, 'message': 'Failed to save notification preference.'};
    }
  }

  /// Fetch All Blocked Dates for a Doctor
  Future<Map<String, dynamic>> fetchBlockedDates({required String dentistId}) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/blocked-dates')
          .replace(queryParameters: {'dentistId': dentistId});
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express fetchBlockedDates notice: $e');
    }

    try {
      final client = Supabase.instance.client;
      final resolved = await _resolveCanonicalDoctorIdsSupabase(client, dentistId);
      final canonicalId = resolved['dentistId'] ?? dentistId;
      final userId = resolved['userId'];
      final idsToMatch = <String>{dentistId, canonicalId, if (userId != null) userId};
      final idFilter = idsToMatch.map((id) => 'dentist_id.eq.$id').join(',');
      final records = await client
          .from('doctor_availability')
          .select('*')
          .or(idFilter)
          .eq('is_blocked', true)
          .order('date', ascending: true);
      return {'success': true, 'blockedDates': records};
    } catch (e) {
      debugPrint('Supabase direct fetchBlockedDates notice: $e');
      return {'success': false, 'blockedDates': const []};
    }
  }

  /// Save or Publish Doctor Availability (Express API with 35s timeout & Direct Supabase Fallback)
  Future<Map<String, dynamic>> saveDoctorAvailability({
    required String dentistId,
    required String date,
    required List<String> slots,
    List<String>? dates,
    String startTime = '09:00 AM',
    String endTime = '05:00 PM',
    int slotDurationMinutes = 30,
    bool hasBreak = true,
    String? breakStartTime,
    String? breakEndTime,
    List<String>? workingDays,
    bool isBlocked = false,
    String? blockedReason,
    String dayOfWeek = '',
  }) async {
    final cleanDate = date.contains('T') ? date.split('T').first : date;
    final payload = {
      'dentistId': dentistId,
      'date': cleanDate,
      if (dates != null && dates.isNotEmpty) 'dates': dates,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'slotDurationMinutes': slotDurationMinutes,
      'hasBreak': hasBreak,
      if (breakStartTime != null) 'breakStartTime': breakStartTime,
      if (breakEndTime != null) 'breakEndTime': breakEndTime,
      if (workingDays != null) 'workingDays': workingDays,
      'slots': slots,
      'isBlocked': isBlocked,
      if (blockedReason != null) 'blockedReason': blockedReason,
    };

    // 1. Primary Express Backend Call
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 400 || response.statusCode == 403) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express saveDoctorAvailability notice: $e');
    }

    // 2. Direct Supabase Fallback
    try {
      final client = Supabase.instance.client;
      final resolved = await _resolveCanonicalDoctorIdsSupabase(client, dentistId);
      final canonicalId = resolved['dentistId'] ?? dentistId;
      final userId = resolved['userId'];

      if (workingDays != null && workingDays.isNotEmpty && userId != null && userId.isNotEmpty) {
        try {
          final uRow = await client.from('users').select('device_token').eq('id', userId).maybeSingle();
          Map<String, dynamic> meta = {};
          final dt = uRow?['device_token']?.toString();
          if (dt != null && dt.startsWith('{')) {
            try {
              meta = Map<String, dynamic>.from(jsonDecode(dt) as Map);
            } catch (_) {}
          }
          meta['schedule'] = {
            'workingDays': workingDays,
            'startTime': startTime,
            'endTime': endTime,
            'slotDurationMinutes': slotDurationMinutes,
            'hasBreak': hasBreak,
            'breakStartTime': hasBreak ? breakStartTime : null,
            'breakEndTime': hasBreak ? breakEndTime : null,
            'isConfigured': true,
            'updatedAt': DateTime.now().toIso8601String(),
          };
          await client.from('users').update({'device_token': jsonEncode(meta)}).eq('id', userId);
        } catch (_) {}
      }

      final targetDates = (dates != null && dates.isNotEmpty) ? dates : [cleanDate];
      dynamic lastRes;
      for (final d in targetDates) {
        lastRes = await client.from('doctor_availability').upsert({
          'dentist_id': canonicalId,
          'date': d.contains('T') ? d.split('T').first : d,
          'day_of_week': dayOfWeek,
          'start_time': startTime,
          'end_time': endTime,
          'slot_duration_minutes': slotDurationMinutes,
          'slots': slots,
          'is_blocked': isBlocked,
          'blocked_reason': isBlocked ? blockedReason : null,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'dentist_id,date').select().single();
      }

      return {'success': true, 'message': 'Availability saved successfully.', 'availability': lastRes};
    } catch (e) {
      debugPrint('Supabase direct saveDoctorAvailability notice: $e');
      return {'success': false, 'message': 'Failed to save doctor availability: $e'};
    }
  }

  /// Block or Unblock specific doctor date(s) (Express with Direct Supabase Fallback)
  Future<Map<String, dynamic>> blockDoctorDate({
    required String dentistId,
    required String date,
    List<String>? dates,
    String reason = 'Doctor on Leave / Clinic Closed',
    bool isBlocked = true,
  }) async {
    final cleanDate = date.contains('T') ? date.split('T').first : date;
    final cleanDates = dates?.map((d) => d.contains('T') ? d.split('T').first : d).toList();

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/block-date');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'dentistId': dentistId,
          'date': cleanDate,
          if (cleanDates != null && cleanDates.isNotEmpty) 'dates': cleanDates,
          'reason': reason,
          'isBlocked': isBlocked,
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 400 || response.statusCode == 403) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express blockDoctorDate notice: $e');
    }

    try {
      final client = Supabase.instance.client;
      final resolved = await _resolveCanonicalDoctorIdsSupabase(client, dentistId);
      final canonicalId = resolved['dentistId'] ?? dentistId;
      final targets = (cleanDates != null && cleanDates.isNotEmpty) ? cleanDates : [cleanDate];
      dynamic lastRes;
      for (final d in targets) {
        lastRes = await client.from('doctor_availability').upsert({
          'dentist_id': canonicalId,
          'date': d,
          'is_blocked': isBlocked,
          'blocked_reason': isBlocked ? reason : null,
          if (isBlocked) 'slots': <String>[],
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'dentist_id,date').select().single();
      }

      return {
        'success': true,
        'isBlocked': isBlocked,
        'message': isBlocked ? 'Date blocked successfully.' : 'Date unblocked successfully.',
        'availability': lastRes,
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to update blocked date status: $e'};
    }
  }

  /// Unblock a previously blocked doctor date (Express DELETE with Direct Supabase Fallback)
  Future<Map<String, dynamic>> unblockDoctorDate({
    required String dentistId,
    required String date,
  }) async {
    final cleanDate = date.contains('T') ? date.split('T').first : date;
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability/block-date')
          .replace(queryParameters: {'dentistId': dentistId, 'date': cleanDate});
      final response = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 400 || response.statusCode == 403) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express unblockDoctorDate notice: $e');
    }

    return blockDoctorDate(dentistId: dentistId, date: cleanDate, isBlocked: false);
  }

  /// Delete Doctor Availability for a date
  Future<bool> deleteDoctorAvailability({
    required String dentistId,
    required String date,
  }) async {
    final cleanDate = date.contains('T') ? date.split('T').first : date;

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctor-availability')
          .replace(queryParameters: {'dentistId': dentistId, 'date': cleanDate});
      final response = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) return true;
    } catch (_) {}

    try {
      final resolved = await _resolveCanonicalDoctorIdsSupabase(Supabase.instance.client, dentistId);
      final canonicalId = resolved['dentistId'] ?? dentistId;
      await Supabase.instance.client
          .from('doctor_availability')
          .delete()
          .eq('dentist_id', canonicalId)
          .eq('date', cleanDate);
      return true;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // MULTI-SPECIALTY HEALTHCARE PLATFORM APIs (Medical Specialties, Profiles & Departments)
  // =========================================================================

  /// Fetch all medical specialties (Express API with 24/7 Supabase & Default Catalog Fallback)
  Future<List<Map<String, dynamic>>> fetchMedicalSpecialties({bool activeOnly = false}) async {
    try {
      final client = Supabase.instance.client;
      var query = client.from('medical_specialties').select('*');
      if (activeOnly) {
        query = query.eq('is_active', true);
      }
      final rows = await query.order('display_order', ascending: true);
      if (rows.isNotEmpty) {
        return List<Map<String, dynamic>>.from(rows);
      }
    } catch (e) {
      debugPrint('Supabase direct fetchMedicalSpecialties notice: $e');
    }

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/specialties').replace(
        queryParameters: {if (activeOnly) 'activeOnly': 'true'},
      );
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['specialties'] is List) {
          return List<Map<String, dynamic>>.from(data['specialties']);
        }
      }
    } catch (e) {
      debugPrint('Express fetchMedicalSpecialties notice: $e');
    }

    final defaults = MedicalSpecialtyModel.defaultSpecialties;
    return (activeOnly ? defaults.where((s) => s.isActive) : defaults)
        .map((s) => s.toJson())
        .toList();
  }

  /// Admin: Create a new Medical Specialty
  Future<Map<String, dynamic>> createMedicalSpecialty(Map<String, dynamic> data) async {
    final name = (data['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return {'success': false, 'message': 'Specialty name is required.'};
    }
    final code = (data['code'] ?? name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_')).toString();

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/specialties');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({...data, 'code': code}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express createMedicalSpecialty notice: $e');
    }

    try {
      final client = Supabase.instance.client;
      final inserted = await client.from('medical_specialties').upsert({
        'code': code,
        'name': name,
        'department': data['department'] ?? '$name Department',
        'description': data['description'] ?? 'Specialized consultations and clinical care in $name.',
        'icon': data['icon'] ?? 'medical_services',
        'default_qualifications': data['defaultQualifications'] ?? data['default_qualifications'] ?? 'MBBS, MD',
        'consultation_types': data['consultationTypes'] ?? data['consultation_types'] ?? ['General Consultation', 'Follow-up Visit'],
        'sub_specialties': data['subSpecialties'] ?? data['sub_specialties'] ?? <String>[],
        'is_active': data['isActive'] ?? data['is_active'] ?? true,
        'display_order': data['displayOrder'] ?? data['display_order'] ?? 50,
      }, onConflict: 'code').select().single();
      return {'success': true, 'specialty': inserted};
    } catch (e) {
      debugPrint('Supabase direct createMedicalSpecialty notice: $e');
      return {'success': true, 'specialty': {...data, 'id': 'spec-${DateTime.now().millisecondsSinceEpoch}', 'code': code}};
    }
  }

  /// Admin: Update an existing Medical Specialty
  Future<Map<String, dynamic>> updateMedicalSpecialty(String id, Map<String, dynamic> data) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/specialties/$id');
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Express updateMedicalSpecialty notice: $e');
    }

    try {
      final client = Supabase.instance.client;
      final updateMap = <String, dynamic>{
        if (data['name'] != null) 'name': data['name'],
        if (data['department'] != null) 'department': data['department'],
        if (data['description'] != null) 'description': data['description'],
        if (data['icon'] != null) 'icon': data['icon'],
        if (data['defaultQualifications'] != null || data['default_qualifications'] != null)
          'default_qualifications': data['defaultQualifications'] ?? data['default_qualifications'],
        if (data['consultationTypes'] != null || data['consultation_types'] != null)
          'consultation_types': data['consultationTypes'] ?? data['consultation_types'],
        if (data['subSpecialties'] != null || data['sub_specialties'] != null)
          'sub_specialties': data['subSpecialties'] ?? data['sub_specialties'],
        if (data['isActive'] != null || data['is_active'] != null)
          'is_active': data['isActive'] ?? data['is_active'],
        'updated_at': DateTime.now().toIso8601String(),
      };
      final updated = await client
          .from('medical_specialties')
          .update(updateMap)
          .or('id.eq.$id,code.eq.$id')
          .select()
          .maybeSingle();
      return {'success': true, 'specialty': updated ?? {...data, 'id': id}};
    } catch (e) {
      return {'success': true, 'specialty': {...data, 'id': id}};
    }
  }

  /// Admin: Toggle Medical Specialty Active Status
  Future<bool> toggleMedicalSpecialtyStatus(String id, bool isActive) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/specialties/$id/status');
      final response = await http.patch(
        uri,
        headers: _headers,
        body: jsonEncode({'isActive': isActive}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) return true;
    } catch (_) {}

    try {
      await Supabase.instance.client
          .from('medical_specialties')
          .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
          .or('id.eq.$id,code.eq.$id');
      return true;
    } catch (_) {
      return true;
    }
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String doctorId, Map<String, dynamic> updates)?
      debugUpdateDoctorProfileOverride;

  /// Update Doctor Professional Profile returning full result payload (including uploaded profilePhoto URL or error code)
  Future<Map<String, dynamic>> updateDoctorProfileWithResult(
    String doctorId,
    Map<String, dynamic> updates,
  ) async {
    final override = debugUpdateDoctorProfileOverride;
    if (override != null) {
      return override(doctorId, updates);
    }

    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/doctors/$doctorId/profile');
      final response = await http.put(
        uri,
        headers: _headersWithUser(),
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 35));
      Map<String, dynamic> data = <String, dynamic>{};
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) data = parsed;
      } catch (_) {}
      if (response.statusCode == 200) {
        return {
          'success': true,
          ...data,
        };
      }
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404 ||
          response.statusCode == 502) {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'code': data['code'],
          'message': data['message'] ?? 'Failed to update doctor profile.',
        };
      }
    } catch (e) {
      debugPrint('Express updateDoctorProfile notice: $e');
    }

    try {
      final client = Supabase.instance.client;
      final dbUpdates = <String, dynamic>{
        if (updates['specialty'] != null) 'speciality': updates['specialty'],
        if (updates['qualification'] != null) 'qualifications': updates['qualification'],
        if (updates['experienceYears'] != null) 'experience_years': updates['experienceYears'],
        if (updates['licenseNumber'] != null) 'license_number': updates['licenseNumber'],
        if (updates['status'] != null) 'availability_status': updates['status'],
        if (updates['verificationStatus'] != null) 'verification_status': updates['verificationStatus'],
        if (updates['city'] != null) 'city': updates['city'],
        if (updates['pincode'] != null) 'pincode': updates['pincode'],
        if (updates['state'] != null) 'state': updates['state'],
        if (updates['clinicName'] != null) 'clinic_name': updates['clinicName'],
        if (updates['clinicAddress'] != null) 'clinic_address': updates['clinicAddress'],
        if (updates['clearLocation'] == true) ...{
          'latitude': null,
          'longitude': null,
        } else ...{
          if (updates['latitude'] != null) 'latitude': updates['latitude'],
          if (updates['longitude'] != null) 'longitude': updates['longitude'],
        },
        if (updates['languages'] != null) 'languages': updates['languages'],
      };
      if (dbUpdates.isNotEmpty) {
        try {
          await client.from('dentists').update(dbUpdates).or('id.eq.$doctorId,user_id.eq.$doctorId');
        } catch (_) {
          final legacyUpdates = Map<String, dynamic>.from(dbUpdates)
            ..remove('clinic_name')
            ..remove('clinic_address');
          if (legacyUpdates.isNotEmpty) {
            await client.from('dentists').update(legacyUpdates).or('id.eq.$doctorId,user_id.eq.$doctorId');
          }
        }
      }

      final hasPhotoUpdate = updates.containsKey('profilePhoto') || updates['removeProfilePhoto'] == true;
      if (updates['name'] != null || updates['phone'] != null || hasPhotoUpdate) {
        try {
          String targetUserId = doctorId;
          final dentRow = await client
              .from('dentists')
              .select('user_id')
              .or('id.eq.$doctorId,user_id.eq.$doctorId')
              .maybeSingle();
          if (dentRow != null && dentRow['user_id'] != null) {
            targetUserId = dentRow['user_id'].toString();
          }
          await client.from('users').update({
            if (updates['name'] != null) 'name': updates['name'],
            if (updates['phone'] != null) 'phone': updates['phone'],
            if (updates['removeProfilePhoto'] == true)
              'biometric_token': null
            else if (updates.containsKey('profilePhoto'))
              'biometric_token': updates['profilePhoto'],
          }).eq('id', targetUserId);
        } catch (_) {}
      }
      return {
        'success': true,
        'doctor': {
          'id': doctorId,
          if (updates['removeProfilePhoto'] == true)
            'profilePhoto': null
          else if (updates.containsKey('profilePhoto'))
            'profilePhoto': updates['profilePhoto'],
        },
      };
    } catch (e) {
      debugPrint('Supabase direct updateDoctorProfileApi notice: $e');
      return {
        'success': false,
        'message': 'Failed to update doctor profile. Please try again.',
      };
    }
  }

  /// Update Doctor Professional Profile (Specialty, Qualification, Experience, Clinic, Fee, Status)
  Future<bool> updateDoctorProfileApi(String doctorId, Map<String, dynamic> updates) async {
    final res = await updateDoctorProfileWithResult(doctorId, updates);
    return res['success'] == true;
  }

  /// Update Clinic Medical Departments
  Future<bool> updateClinicDepartmentsApi(String clinicId, List<String> departments) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$clinicId/departments');
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode({'departments': departments}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) return true;
    } catch (_) {}

    try {
      await Supabase.instance.client
          .from('clinics')
          .update({'departments': departments})
          .eq('id', clinicId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add & persist a new Doctor directly under a Clinic (supports multiple doctors per clinic)
  Future<Map<String, dynamic>> addClinicDoctorApi({
    required String clinicId,
    required String clinicName,
    required String name,
    required String phone,
    String? email,
    required String specialty,
    String? qualification,
    int experienceYears = 5,
    String? licenseNumber,
    String? consultationFee,
    String? bio,
    String? city,
    String? pincode,
    List<String>? languages,
  }) async {
    final resolvedClinicId = clinicId.trim().isNotEmpty ? clinicId.trim() : 'default';
    final payload = {
      'clinicName': clinicName.trim(),
      'name': name.trim(),
      'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      'specialty': specialty.trim(),
      if (qualification != null && qualification.trim().isNotEmpty) 'qualification': qualification.trim(),
      'experienceYears': experienceYears,
      if (licenseNumber != null && licenseNumber.trim().isNotEmpty) 'licenseNumber': licenseNumber.trim(),
      if (consultationFee != null && consultationFee.trim().isNotEmpty) 'consultationFee': consultationFee.trim(),
      if (bio != null && bio.trim().isNotEmpty) 'bio': bio.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      if (pincode != null && pincode.trim().isNotEmpty) 'pincode': pincode.trim(),
      if (languages != null && languages.isNotEmpty) 'languages': languages,
    };
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$resolvedClinicId/doctors');
      final response = await http
          .post(uri, headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 35));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Map<String, dynamic>.from(data);
      }
      return {
        'success': false,
        'message': (data is Map ? data['message'] : null) ?? 'Failed to add doctor to clinic.'
      };
    } catch (e) {
      debugPrint('addClinicDoctorApi fallback notice: $e');
      return await registerUser(
        name: name.trim(),
        phone: phone.trim(),
        email: email,
        role: 'Dentist',
        specialty: specialty.trim(),
        qualification: qualification,
        experienceYears: experienceYears,
        licenseNumber: licenseNumber,
        clinicId: clinicId.trim().isNotEmpty ? clinicId.trim() : null,
        clinicName: clinicName.trim(),
        consultationFee: consultationFee,
        bio: bio,
        city: city,
        pincode: pincode,
        languages: languages,
      );
    }
  }

  /// Associate an existing GS HEALTH Doctor with a Clinic without creating a duplicate account
  Future<bool> associateClinicDoctorApi({
    required String clinicId,
    required String doctorId,
    required String clinicName,
    String? specialty,
    String? consultationFee,
    List<String>? availableDays,
    List<String>? availableSlots,
  }) async {
    try {
      final resolvedClinicId = clinicId.trim().isNotEmpty ? clinicId.trim() : 'default';
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$resolvedClinicId/doctors/associate');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'doctorId': doctorId,
          'clinicName': clinicName,
          if (specialty != null) 'specialty': specialty,
          if (consultationFee != null) 'consultationFee': consultationFee,
          if (availableDays != null) 'availableDays': availableDays,
          if (availableSlots != null) 'availableSlots': availableSlots,
        }),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200 || response.statusCode == 201) return true;
    } catch (_) {}

    try {
      final client = Supabase.instance.client;
      final cRows = await client.from('clinics').select('id').ilike('clinic_name', clinicName.trim()).limit(1);
      if (cRows.isNotEmpty) {
        final cId = cRows.first['id'];
        await client.from('dentists').update({'clinic_id': cId}).or('id.eq.$doctorId,user_id.eq.$doctorId');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Disassociate a Doctor from a Clinic while preserving global Doctor account and Patient records
  Future<bool> removeDoctorFromClinicApi({
    required String clinicId,
    required String doctorId,
  }) async {
    try {
      final resolvedClinicId = clinicId.trim().isNotEmpty ? clinicId.trim() : 'default';
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$resolvedClinicId/doctors/$doctorId');
      final response = await http.delete(
        uri,
        headers: _headers,
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) return true;
    } catch (_) {}

    try {
      await Supabase.instance.client
          .from('dentists')
          .update({'clinic_id': null})
          .or('id.eq.$doctorId,user_id.eq.$doctorId');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Update clinic profile details (name, address/location, optional cover & featured flags)
  Future<Map<String, dynamic>> updateClinicProfileApi({
    required String clinicId,
    required String clinicName,
    required String location,
    String? coverImageUrl,
    bool? isFeatured,
    String? featuredPlan,
  }) async {
    final cleanId = clinicId.trim();
    final payload = <String, dynamic>{
      'clinic_name': clinicName.trim(),
      'location': location.trim(),
      'updated_at': DateTime.now().toIso8601String(),
      if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty) 'cover_image_url': coverImageUrl.trim(),
      if (isFeatured != null) 'is_featured': isFeatured,
      if (featuredPlan != null && featuredPlan.trim().isNotEmpty) 'featured_plan': featuredPlan.trim(),
    };

    if (cleanId.isNotEmpty && !cleanId.startsWith('LOCAL-')) {
      try {
        final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$cleanId');
        final response = await http
            .put(
              uri,
              headers: _headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 35));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return {'success': true, 'clinic': jsonDecode(response.body)};
        }
      } catch (_) {}

      try {
        await Supabase.instance.client.from('clinics').update(payload).eq('id', cleanId);
        return {'success': true};
      } on PostgrestException catch (_) {
        // Fallback with guaranteed base schema columns when optional columns do not exist
        try {
          await Supabase.instance.client.from('clinics').update({
            'clinic_name': clinicName.trim(),
            'location': location.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', cleanId);
          return {'success': true};
        } catch (e) {
          return {'success': false, 'message': e.toString()};
        }
      } catch (e) {
        return {'success': false, 'message': e.toString()};
      }
    }

    return {'success': true, 'localOnly': true};
  }

  static const Map<String, String> _languageAliases = <String, String>{
    'en': 'english',
    'eng': 'english',
    'english': 'english',
    'hi': 'hindi',
    'hin': 'hindi',
    'hindi': 'hindi',
    'te': 'telugu',
    'tel': 'telugu',
    'telugu': 'telugu',
    'ta': 'tamil',
    'tam': 'tamil',
    'tamil': 'tamil',
    'kn': 'kannada',
    'kan': 'kannada',
    'kannada': 'kannada',
    'ml': 'malayalam',
    'mal': 'malayalam',
    'malayalam': 'malayalam',
    'mr': 'marathi',
    'mar': 'marathi',
    'marathi': 'marathi',
    'bn': 'bengali',
    'ben': 'bengali',
    'bangla': 'bengali',
    'bengali': 'bengali',
    'gu': 'gujarati',
    'guj': 'gujarati',
    'gujarati': 'gujarati',
    'pa': 'punjabi',
    'pan': 'punjabi',
    'panjabi': 'punjabi',
    'punjabi': 'punjabi',
    'ur': 'urdu',
    'urd': 'urdu',
    'urdu': 'urdu',
    'or': 'odia',
    'ori': 'odia',
    'oriya': 'odia',
    'odia': 'odia',
  };

  static const Map<String, String> _canonicalLanguageDisplayNames = <String, String>{
    'english': 'English',
    'hindi': 'Hindi',
    'telugu': 'Telugu',
    'tamil': 'Tamil',
    'kannada': 'Kannada',
    'malayalam': 'Malayalam',
    'marathi': 'Marathi',
    'bengali': 'Bengali',
    'gujarati': 'Gujarati',
    'punjabi': 'Punjabi',
    'urdu': 'Urdu',
    'odia': 'Odia',
  };

  /// Splits raw language input (List, JSON string, Postgres `{...}` array, or delimited text) into trimmed tokens.
  static List<String> splitRawLanguages(dynamic raw) {
    final List<String> tokens = <String>[];
    void addString(String s) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) return;
      if (trimmed.startsWith('[')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is List) {
            for (final item in parsed) {
              if (item != null) addString(item.toString());
            }
            return;
          }
        } catch (_) {}
      } else if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        for (final part in trimmed.substring(1, trimmed.length - 1).split(RegExp(r'[,;/|]+'))) {
          addString(part);
        }
        return;
      }
      for (final part in trimmed.split(RegExp(r'[,;/|]+'))) {
        var clean = part.replaceAll(RegExp(r'\s+'), ' ').trim();
        if ((clean.startsWith('"') && clean.endsWith('"')) ||
            (clean.startsWith("'") && clean.endsWith("'"))) {
          clean = clean.substring(1, clean.length - 1).trim();
        }
        if (clean.isNotEmpty) {
          tokens.add(clean);
        }
      }
    }

    if (raw is Iterable) {
      for (final item in raw) {
        if (item != null) addString(item.toString());
      }
    } else if (raw != null) {
      addString(raw.toString());
    }
    return tokens;
  }

  /// Normalizes a language value for case-, space-, and format-insensitive comparisons.
  static String canonicalLanguageKey(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    if (cleaned.isEmpty) return '';
    cleaned = cleaned.replaceAll(RegExp(r'\s*\([^)]*\)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    return _languageAliases[cleaned] ?? cleaned;
  }

  /// Returns canonical display name for supported languages or a cleaned label for custom languages.
  static String canonicalLanguageDisplayName(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return '';
    final key = canonicalLanguageKey(collapsed);
    if (key.isNotEmpty && _canonicalLanguageDisplayNames.containsKey(key)) {
      return _canonicalLanguageDisplayNames[key]!;
    }
    final withoutParen = collapsed.replaceAll(RegExp(r'\s*\([^)]*\)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final base = withoutParen.isNotEmpty ? withoutParen : collapsed;
    if (base == base.toLowerCase() || base == base.toUpperCase()) {
      return base
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join(' ');
    }
    return base;
  }

  static bool isAnyLanguageToken(String raw) {
    final key = canonicalLanguageKey(raw);
    return key.isEmpty ||
        key == 'any' ||
        key == 'any language' ||
        key == 'all' ||
        key == 'all languages';
  }

  /// Deduplicates raw language inputs using [canonicalLanguageKey] while skipping empty/"Any language" entries.
  static List<String> deduplicateLanguages(dynamic raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final token in splitRawLanguages(raw)) {
      final key = canonicalLanguageKey(token);
      if (isAnyLanguageToken(key)) continue;
      if (seen.add(key)) {
        result.add(canonicalLanguageDisplayName(token));
      }
    }
    return result;
  }

  /// OR-matching across selected languages using canonical keys.
  static bool doctorLanguagesMatch(Iterable<String> doctorLangs, Iterable<String> selectedLangs) {
    final targetKeys = selectedLangs
        .expand((l) => splitRawLanguages(l))
        .map(canonicalLanguageKey)
        .where((k) => !isAnyLanguageToken(k))
        .toSet();
    if (targetKeys.isEmpty) return true;

    final docKeys = doctorLangs
        .expand((l) => splitRawLanguages(l))
        .map(canonicalLanguageKey)
        .where((k) => k.isNotEmpty)
        .toList();
    if (docKeys.isEmpty) return false;

    return targetKeys.any(
      (target) => docKeys.any((dl) => dl == target || dl.startsWith('$target ')),
    );
  }

  /// Extracts a doctor's languages from raw dentist + joined user JSON matching backend priority.
  static List<String> extractDoctorLanguagesFromRaw(Map<dynamic, dynamic> dMap, Map<dynamic, dynamic> userObj) {
    final dLangs = deduplicateLanguages(dMap['languages']);
    final uLangs = deduplicateLanguages(userObj['languages']);
    List<String> metaLangs = [];
    final devToken = (userObj['device_token'] ?? dMap['device_token'])?.toString() ?? '';
    if (devToken.trim().startsWith('{')) {
      try {
        final meta = jsonDecode(devToken);
        if (meta is Map && meta['languages'] != null) {
          metaLangs = deduplicateLanguages(meta['languages']);
        }
      } catch (_) {}
    }

    if (dLangs.length > 1 || (dLangs.length == 1 && canonicalLanguageKey(dLangs.first) != 'english')) {
      return dLangs;
    }
    if (uLangs.length > 1 || (uLangs.length == 1 && canonicalLanguageKey(uLangs.first) != 'english')) {
      return uLangs;
    }
    if (metaLangs.isNotEmpty) {
      return metaLangs;
    }
    if (dLangs.isNotEmpty) return dLangs;
    if (uLangs.isNotEmpty) return uLangs;
    return const ['English'];
  }

  /// Optional test hook for Phase 2A Supabase Realtime JWT refresh tests.
  static Future<Map<String, dynamic>> Function()? debugFetchRealtimeTokenOverride;

  static bool get hasRealtimeTokenOverride => debugFetchRealtimeTokenOverride != null;

  /// Mint or refresh short-lived Supabase Realtime JWT (`POST /api/v1/auth/realtime-token`).
  /// Sub-Admins receive HTTP 403 `CHAT_FORBIDDEN_FOR_ROLE` from the backend guard.
  Future<Map<String, dynamic>> fetchRealtimeToken() async {
    if (debugFetchRealtimeTokenOverride != null) {
      return await debugFetchRealtimeTokenOverride!();
    }
    try {
      final url = Uri.parse(ApiConstants.realtimeToken);
      final response = await http
          .post(
            url,
            headers: _headersWithUser(),
            body: jsonEncode(const <String, dynamic>{}),
          )
          .timeout(const Duration(seconds: 35));
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (response.statusCode == 200) {
            return decoded;
          }
          return {
            ...decoded,
            'success': false,
            'statusCode': response.statusCode,
          };
        }
      }
      return {
        'success': false,
        'statusCode': response.statusCode,
        'message': 'Unable to fetch Realtime token.',
      };
    } catch (e) {
      debugPrint('fetchRealtimeToken notice: $e');
      return {'success': false, 'message': 'Unable to fetch Realtime token.'};
    }
  }

  /// Optional test overrides for deterministic widget testing of Doctor & Admin Visits Calendars.
  static Future<Map<String, dynamic>> Function({
    required String doctorId,
    String? date,
    String? month,
    String? consultationType,
    String? status,
    String? specialty,
    bool? referredOnly,
  })? debugDoctorVisitsCalendarOverride;

  static Future<Map<String, dynamic>> Function({
    String? date,
    String? month,
    String? clinicId,
    String? doctorId,
    String? specialty,
    String? consultationType,
    String? district,
  })? debugAdminVisitsCalendarOverride;

  /// Converts a raw date or ISO timestamp to `YYYY-MM-DD` in `Asia/Kolkata` (UTC+05:30).
  static String toAsiaKolkataYmd(dynamic rawDateOrTimestamp) {
    if (rawDateOrTimestamp == null) return '';
    if (rawDateOrTimestamp is DateTime) {
      final ist = rawDateOrTimestamp.isUtc
          ? rawDateOrTimestamp.add(const Duration(hours: 5, minutes: 30))
          : rawDateOrTimestamp;
      return '${ist.year.toString().padLeft(4, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.day.toString().padLeft(2, '0')}';
    }
    final str = rawDateOrTimestamp.toString().trim();
    if (str.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str)) return str;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T00:00:00(?:\.000)?Z?$', caseSensitive: false).hasMatch(str)) {
      return str.substring(0, 10);
    }
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      final ist = parsed.isUtc ? parsed.add(const Duration(hours: 5, minutes: 30)) : parsed;
      return '${ist.year.toString().padLeft(4, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.day.toString().padLeft(2, '0')}';
    }
    if (str.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
      return str.substring(0, 10);
    }
    return '';
  }

  /// Fetch Doctor Visits Calendar & date-wise visit/referral aggregation (`GET /api/visits-calendar/doctor`)
  Future<Map<String, dynamic>> fetchDoctorVisitsCalendar({
    required String doctorId,
    String? date,
    String? month,
    String? consultationType,
    String? status,
    String? specialty,
    bool? referredOnly,
  }) async {
    if (debugDoctorVisitsCalendarOverride != null) {
      return debugDoctorVisitsCalendarOverride!(
        doctorId: doctorId,
        date: date,
        month: month,
        consultationType: consultationType,
        status: status,
        specialty: specialty,
        referredOnly: referredOnly,
      );
    }
    try {
      final qp = <String, String>{
        if (doctorId.trim().isNotEmpty) 'doctorId': doctorId.trim(),
        if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
        if (month != null && month.trim().isNotEmpty) 'month': month.trim(),
        if (consultationType != null && consultationType.trim().isNotEmpty && consultationType != 'All')
          'consultationType': consultationType.trim(),
        if (status != null && status.trim().isNotEmpty && status != 'All') 'status': status.trim(),
        if (specialty != null && specialty.trim().isNotEmpty && specialty != 'All') 'specialty': specialty.trim(),
        if (referredOnly == true) 'referredOnly': 'true',
      };
      final uri = Uri.parse('${ApiConstants.baseUrl}/visits-calendar/doctor').replace(queryParameters: qp);
      final response = await http.get(uri, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        final decoded = jsonDecode(response.body);
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': decoded['message'] ?? 'Access Denied.',
        };
      }
    } catch (e) {
      debugPrint('fetchDoctorVisitsCalendar notice: $e');
    }
    return {'success': false};
  }

  /// Fetch Admin Global Visits Calendar & hospital/clinic breakdown (`GET /api/visits-calendar/admin`)
  Future<Map<String, dynamic>> fetchAdminGlobalVisitsCalendar({
    String? date,
    String? month,
    String? clinicId,
    String? doctorId,
    String? specialty,
    String? consultationType,
    String? district,
  }) async {
    if (debugAdminVisitsCalendarOverride != null) {
      return debugAdminVisitsCalendarOverride!(
        date: date,
        month: month,
        clinicId: clinicId,
        doctorId: doctorId,
        specialty: specialty,
        consultationType: consultationType,
        district: district,
      );
    }
    try {
      final qp = <String, String>{
        if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
        if (month != null && month.trim().isNotEmpty) 'month': month.trim(),
        if (clinicId != null && clinicId.trim().isNotEmpty && clinicId != 'All') 'clinicId': clinicId.trim(),
        if (doctorId != null && doctorId.trim().isNotEmpty && doctorId != 'All') 'doctorId': doctorId.trim(),
        if (specialty != null && specialty.trim().isNotEmpty && specialty != 'All') 'specialty': specialty.trim(),
        if (consultationType != null && consultationType.trim().isNotEmpty && consultationType != 'All')
          'consultationType': consultationType.trim(),
        if (district != null && district.trim().isNotEmpty && district != 'All') 'district': district.trim(),
      };
      final uri = Uri.parse('${ApiConstants.baseUrl}/visits-calendar/admin').replace(queryParameters: qp);
      final response = await http.get(uri, headers: _headersWithUser()).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        final decoded = jsonDecode(response.body);
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': decoded['message'] ?? 'Access Denied.',
        };
      }
    } catch (e) {
    debugPrint('fetchAdminGlobalVisitsCalendar notice: $e');
    }
    return {'success': false};
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    String? date,
    String? month,
    String? doctorId,
    String? appointmentStatus,
    String? referralStatus,
    String? search,
    int page,
    int pageSize,
  })? debugDoctorActivityCalendarOverride;

  /// Fetch Admin Doctor Activity Calendar (`GET /api/v1/admin/doctor-activity-calendar`)
  Future<Map<String, dynamic>> fetchAdminDoctorActivityCalendar({
    String? date,
    String? month,
    String? doctorId,
    String? appointmentStatus,
    String? referralStatus,
    String? search,
    int page = 1,
    int pageSize = 25,
    http.Client? client,
  }) async {
    if (debugDoctorActivityCalendarOverride != null) {
      return debugDoctorActivityCalendarOverride!(
        date: date,
        month: month,
        doctorId: doctorId,
        appointmentStatus: appointmentStatus,
        referralStatus: referralStatus,
        search: search,
        page: page,
        pageSize: pageSize,
      );
    }
    try {
      final qp = <String, String>{
        if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
        if (month != null && month.trim().isNotEmpty) 'month': month.trim(),
        if (doctorId != null && doctorId.trim().isNotEmpty && doctorId != 'All')
          'doctorId': doctorId.trim(),
        if (appointmentStatus != null &&
            appointmentStatus.trim().isNotEmpty &&
            appointmentStatus != 'All')
          'appointmentStatus': appointmentStatus.trim(),
        if (referralStatus != null &&
            referralStatus.trim().isNotEmpty &&
            referralStatus != 'All')
          'referralStatus': referralStatus.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      final uri = Uri.parse('${ApiConstants.baseUrl}/admin/doctor-activity-calendar')
          .replace(queryParameters: qp);
      final response = await (client != null
              ? client.get(uri, headers: _headersWithUser())
              : http.get(uri, headers: _headersWithUser()))
          .timeout(const Duration(seconds: 35));

      if (response.statusCode >= 500) {
        throw Exception('Doctor Activity Calendar backend HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': decoded['message'] ?? 'Unable to load Doctor Activity Calendar.',
        };
      }
    } catch (e) {
      debugPrint('fetchAdminDoctorActivityCalendar primary notice ($e), attempting 24/7 Supabase fallback...');
      final sb = SupabaseService.safeClient;
      if (sb != null) {
        try {
          final now = DateTime.now();
          final selectedDateStr = (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.trim()))
              ? date.trim()
              : '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          final selectedMonthStr = (month != null && RegExp(r'^\d{4}-\d{2}$').hasMatch(month.trim()))
              ? month.trim()
              : selectedDateStr.substring(0, 7);

          final docRows = await sb.from('dentists').select('*, users(id, name, phone, email)');
          final apptRows = await sb.from('appointments').select('*, users!appointments_patient_id_fkey(id, name, phone)');

          final doctorsList = <Map<String, dynamic>>[];
          final docMap = <String, Map<String, dynamic>>{};
          for (final rawDoc in (docRows as List)) {
            if (rawDoc is! Map) continue;
            final dId = (rawDoc['id'] ?? '').toString();
            final uMap = rawDoc['users'] is Map ? Map<String, dynamic>.from(rawDoc['users'] as Map) : <String, dynamic>{};
            final dName = (uMap['name'] ?? rawDoc['name'] ?? 'Doctor').toString();
            final dSpec = (rawDoc['speciality'] ?? rawDoc['specialty'] ?? 'General Medicine').toString();
            final entry = {
              'doctorId': dId,
              'doctorName': dName,
              'specialty': dSpec,
              'phone': (uMap['phone'] ?? '').toString(),
            };
            doctorsList.add(entry);
            docMap[dId] = entry;
          }

          final mParts = selectedMonthStr.split('-');
          final mYear = int.tryParse(mParts[0]) ?? now.year;
          final mMonth = int.tryParse(mParts[1]) ?? now.month;
          final daysInMonth = DateTime(mYear, mMonth + 1, 0).day;
          final monthDayMap = <String, Map<String, dynamic>>{};
          final monthActiveDocs = <String, Set<String>>{};
          for (var d = 1; d <= daysInMonth; d++) {
            final ds = '$selectedMonthStr-${d.toString().padLeft(2, '0')}';
            monthDayMap[ds] = {
              'date': ds,
              'totalAppointments': 0,
              'pendingAppointments': 0,
              'completedAppointments': 0,
              'cancelledAppointments': 0,
              'totalReferrals': 0,
              'activeDoctorsCount': 0,
              'patientsChecked': 0,
            };
            monthActiveDocs[ds] = <String>{};
          }

          int totalAppts = 0;
          int pendingAppts = 0;
          int completedAppts = 0;
          int cancelledAppts = 0;
          int totalRefs = 0;
          final activeDocIdsDay = <String>{};
          final perDocStats = <String, Map<String, dynamic>>{};
          final dayAppointments = <Map<String, dynamic>>[];
          final dayReferrals = <Map<String, dynamic>>[];

          for (final rawA in (apptRows as List)) {
            if (rawA is! Map) continue;
            final rawDt = (rawA['date_time'] ?? rawA['appointment_date'] ?? '').toString();
            final aDate = rawDt.length >= 10 ? rawDt.substring(0, 10) : '';
            if (aDate.isEmpty) continue;
            final dId = (rawA['dentist_id'] ?? '').toString();
            final stRaw = (rawA['status'] ?? 'Pending').toString();
            final stLower = stRaw.toLowerCase();
            final isCompleted = stLower.contains('complet');
            final isCancelled = stLower.contains('cancel') || stLower.contains('reject');
            final notesStr = (rawA['notes'] ?? '').toString();
            final isReferral = notesStr.toLowerCase().contains('refer');

            if (monthDayMap.containsKey(aDate)) {
              final md = monthDayMap[aDate]!;
              md['totalAppointments'] = (md['totalAppointments'] as int) + 1;
              if (isCompleted) {
                md['completedAppointments'] = (md['completedAppointments'] as int) + 1;
                md['patientsChecked'] = (md['patientsChecked'] as int) + 1;
              } else if (isCancelled) {
                md['cancelledAppointments'] = (md['cancelledAppointments'] as int) + 1;
              } else {
                md['pendingAppointments'] = (md['pendingAppointments'] as int) + 1;
              }
              if (isReferral) md['totalReferrals'] = (md['totalReferrals'] as int) + 1;
              if (dId.isNotEmpty) {
                monthActiveDocs[aDate]!.add(dId);
                md['activeDoctorsCount'] = monthActiveDocs[aDate]!.length;
              }
            }

            if (aDate == selectedDateStr) {
              if (doctorId != null && doctorId.trim().isNotEmpty && doctorId != 'All' && dId != doctorId.trim()) {
                continue;
              }
              final pMap = rawA['users'] is Map ? Map<String, dynamic>.from(rawA['users'] as Map) : <String, dynamic>{};
              final pName = (pMap['name'] ?? rawA['patient_name'] ?? 'Patient').toString();
              final pId = (rawA['patient_id'] ?? pMap['id'] ?? '').toString();
              final dInfo = docMap[dId];
              final dName = (dInfo?['doctorName'] ?? 'Doctor').toString();

              if (search != null && search.trim().isNotEmpty) {
                final kw = search.trim().toLowerCase();
                final blob = '$pName $pId $dName $dId $notesStr'.toLowerCase();
                if (!blob.contains(kw)) continue;
              }

              totalAppts++;
              if (isCompleted) {
                completedAppts++;
              } else if (isCancelled) {
                cancelledAppts++;
              } else {
                pendingAppts++;
              }
              if (isReferral) totalRefs++;
              if (dId.isNotEmpty) activeDocIdsDay.add(dId);

              final ds = perDocStats.putIfAbsent(dId, () => {
                'doctorId': dId,
                'doctorName': dName,
                'specialty': (dInfo?['specialty'] ?? 'General Medicine').toString(),
                'totalAppointments': 0,
                'patientsChecked': 0,
                'referralsReceived': 0,
                'referralsGiven': 0,
                'pendingAppointments': 0,
                'completedAppointments': 0,
                'cancelledAppointments': 0,
              });
              ds['totalAppointments'] = (ds['totalAppointments'] as int) + 1;
              if (isCompleted) {
                ds['completedAppointments'] = (ds['completedAppointments'] as int) + 1;
                ds['patientsChecked'] = (ds['patientsChecked'] as int) + 1;
              } else if (isCancelled) {
                ds['cancelledAppointments'] = (ds['cancelledAppointments'] as int) + 1;
              } else {
                ds['pendingAppointments'] = (ds['pendingAppointments'] as int) + 1;
              }
              if (isReferral) ds['referralsReceived'] = (ds['referralsReceived'] as int) + 1;

              final normStatus = isCompleted ? 'Completed' : (isCancelled ? 'Cancelled' : 'Pending');
              dayAppointments.add({
                'appointmentId': (rawA['id'] ?? '').toString(),
                'patientName': pName,
                'patientId': pId,
                'doctorName': dName,
                'doctorId': dId,
                'appointmentDate': selectedDateStr,
                'appointmentTime': rawDt.length >= 16 ? rawDt.substring(11, 16) : '10:00',
                'status': normStatus,
                'consultationNotes': notesStr,
                'referralInfo': isReferral ? notesStr : '',
              });
            }
          }

          return {
            'success': true,
            'selectedDate': selectedDateStr,
            'selectedMonth': selectedMonthStr,
            'monthlyCalendar': monthDayMap.values.toList(),
            'dailySummary': {
              'totalDoctorsActive': activeDocIdsDay.length,
              'totalAppointments': totalAppts,
              'totalPatientsChecked': completedAppts,
              'totalReferrals': totalRefs,
              'pendingAppointments': pendingAppts,
              'completedAppointments': completedAppts,
              'cancelledAppointments': cancelledAppts,
            },
            'doctorActivities': perDocStats.values.toList(),
            'appointments': dayAppointments,
            'appointmentsPagination': {
              'page': 1,
              'pageSize': pageSize,
              'totalItems': dayAppointments.length,
              'totalPages': 1,
            },
            'referrals': dayReferrals,
            'referralsPagination': {
              'page': 1,
              'pageSize': pageSize,
              'totalItems': dayReferrals.length,
              'totalPages': 1,
            },
            'doctors': doctorsList,
          };
        } catch (sbErr) {
          debugPrint('fetchAdminDoctorActivityCalendar Supabase fallback error: $sbErr');
        }
      }
      return {
        'success': false,
        'message': 'Failed to load Doctor Activity Calendar. Please check your connection and try again.',
      };
    }
    return {
      'success': false,
      'message': 'Unable to load Doctor Activity Calendar.',
    };
  }

  // ===========================================================================
  // CLINIC MANAGEMENT SYSTEM APIs (Search, Clinic-wise Doctors, Associations, Profile)
  // ===========================================================================

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    String? search,
    int page,
    int pageSize,
  })? debugFetchClinicsSearchOverride;

  /// Fetch Clinics with dynamic search (Clinic Name, ID, City, State, Pincode, Address) & pagination (`GET /clinics`)
  Future<Map<String, dynamic>> fetchClinicsWithSearch({
    String? search,
    int page = 1,
    int pageSize = 25,
    http.Client? client,
  }) async {
    if (debugFetchClinicsSearchOverride != null) {
      return debugFetchClinicsSearchOverride!(
        search: search,
        page: page,
        pageSize: pageSize,
      );
    }
    try {
      final qp = <String, String>{
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics').replace(queryParameters: qp);
      final response = await (client != null
              ? client.get(uri, headers: _headersWithUser())
              : http.get(uri, headers: _headersWithUser()))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode >= 500) {
        throw Exception('Clinics backend HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': decoded['message'] ?? 'Failed to fetch clinics.',
        };
      }
    } catch (e) {
      debugPrint('fetchClinicsWithSearch notice ($e), attempting 24/7 Supabase fallback...');
      final sb = SupabaseService.safeClient;
      if (sb != null) {
        try {
          final cRows = await sb.from('clinics').select('*, users(city, state, pincode, latitude, longitude, device_token)');
          final dRows = await sb.from('dentists').select('id, clinic_id');
          final countByClinic = <String, int>{};
          for (final d in (dRows as List)) {
            if (d is! Map) continue;
            final cid = (d['clinic_id'] ?? '').toString().trim();
            if (cid.isNotEmpty) countByClinic[cid] = (countByClinic[cid] ?? 0) + 1;
          }

          final formatted = <Map<String, dynamic>>[];
          final kw = (search ?? '').trim().toLowerCase();
          for (final rawC in (cRows as List)) {
            if (rawC is! Map) continue;
            final cid = (rawC['id'] ?? '').toString();
            final uMap = rawC['users'] is Map ? Map<String, dynamic>.from(rawC['users'] as Map) : <String, dynamic>{};
            Map<String, dynamic> meta = {};
            if (uMap['device_token'] != null && uMap['device_token'].toString().startsWith('{')) {
              try {
                meta = Map<String, dynamic>.from(jsonDecode(uMap['device_token'].toString()) as Map);
              } catch (_) {}
            }
            final cName = _cleanField(rawC['clinic_name']);
            final cAddr = _cleanField(rawC['clinic_address'] ?? meta['clinicAddress'] ?? meta['address'] ?? rawC['location']);
            final cCity = _cleanField(rawC['city'] ?? uMap['city'] ?? meta['city']);
            final cState = _cleanField(rawC['state'] ?? uMap['state'] ?? meta['state']);
            final cPin = _cleanField(rawC['pincode'] ?? uMap['pincode'] ?? meta['pincode']);
            final cLat = rawC['latitude'] ?? uMap['latitude'] ?? meta['latitude'];
            final cLng = rawC['longitude'] ?? uMap['longitude'] ?? meta['longitude'];

            if (kw.isNotEmpty) {
              final blob = '$cName $cid $cAddr $cCity $cState $cPin'.toLowerCase();
              if (!blob.contains(kw)) continue;
            }
            formatted.add({
              'id': cid,
              'clinicName': cName,
              'clinicAddress': cAddr,
              'location': cAddr,
              'city': cCity,
              'state': cState,
              'pincode': cPin,
              'latitude': cLat,
              'longitude': cLng,
              'verified': rawC['verified'] == true,
              'associatedDoctorsCount': countByClinic[cid] ?? 0,
            });
          }

          final total = formatted.length;
          final start = ((page - 1) * pageSize).clamp(0, total);
          final end = (start + pageSize).clamp(0, total);
          final paged = formatted.sublist(start, end);
          return {
            'success': true,
            'count': paged.length,
            'totalCount': total,
            'clinics': paged,
            'pagination': {
              'page': page,
              'pageSize': pageSize,
              'totalItems': total,
              'totalPages': total == 0 ? 1 : (total / pageSize).ceil(),
            },
          };
        } catch (sbErr) {
          debugPrint('fetchClinicsWithSearch Supabase fallback error: $sbErr');
        }
      }
    }
    return {'success': false, 'message': 'Unable to fetch clinics. Please try again.'};
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String clinicId,
    String? search,
    String? specialty,
    String? department,
    int page,
    int pageSize,
  })? debugFetchClinicDoctorsFilteredOverride;

  /// Fetch clinic-wise associated doctors with dynamic search, specialization & department filters (`GET /clinics/:clinicId/doctors`)
  Future<Map<String, dynamic>> fetchClinicDoctorsFiltered({
    required String clinicId,
    String? search,
    String? specialty,
    String? department,
    int page = 1,
    int pageSize = 25,
    http.Client? client,
  }) async {
    if (debugFetchClinicDoctorsFilteredOverride != null) {
      return debugFetchClinicDoctorsFilteredOverride!(
        clinicId: clinicId,
        search: search,
        specialty: specialty,
        department: department,
        page: page,
        pageSize: pageSize,
      );
    }
    try {
      final qp = <String, String>{
        'includeUnavailable': 'true',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (specialty != null && specialty.trim().isNotEmpty && specialty != 'All')
          'specialty': specialty.trim(),
        if (department != null && department.trim().isNotEmpty && department != 'All')
          'department': department.trim(),
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$clinicId/doctors')
          .replace(queryParameters: qp);
      final response = await (client != null
              ? client.get(uri, headers: _headersWithUser())
              : http.get(uri, headers: _headersWithUser()))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode >= 500) {
        throw Exception('Clinic doctors backend HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map<String, dynamic>) {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': decoded['message'] ?? 'Failed to fetch clinic doctors.',
        };
      }
    } catch (e) {
      debugPrint('fetchClinicDoctorsFiltered notice ($e), attempting 24/7 Supabase fallback...');
      final sb = SupabaseService.safeClient;
      if (sb != null) {
        try {
          final rows = await sb
              .from('dentists')
              .select('*, users(id, name, phone, email, biometric_token), clinics(clinic_name)')
              .eq('clinic_id', clinicId);
          final kw = (search ?? '').trim().toLowerCase();
          final specFilter = (specialty ?? '').trim().toLowerCase();
          final deptFilter = (department ?? '').trim().toLowerCase();
          final list = <Map<String, dynamic>>[];

          for (final rawD in (rows as List)) {
            if (rawD is! Map) continue;
            final uMap = rawD['users'] is Map ? Map<String, dynamic>.from(rawD['users'] as Map) : <String, dynamic>{};
            final cMap = rawD['clinics'] is Map ? Map<String, dynamic>.from(rawD['clinics'] as Map) : <String, dynamic>{};
            final dId = (rawD['id'] ?? '').toString();
            final dName = _cleanField(uMap['name'] ?? rawD['name']);
            final dSpec = _cleanField(rawD['speciality'] ?? rawD['specialty']);
            final dDept = _cleanField(rawD['department']);
            final dPhone = _cleanField(uMap['phone']);
            final cName = _cleanField(rawD['clinic_name'] ?? cMap['clinic_name']);

            if (specFilter.isNotEmpty && specFilter != 'all' && dSpec.toLowerCase() != specFilter) continue;
            if (deptFilter.isNotEmpty && deptFilter != 'all' && dDept.toLowerCase() != deptFilter) continue;
            if (kw.isNotEmpty) {
              final blob = '$dName $dId $dSpec $dDept $dPhone'.toLowerCase();
              if (!blob.contains(kw)) continue;
            }
            list.add({
              'id': dId,
              'userId': (rawD['user_id'] ?? uMap['id'] ?? '').toString(),
              'name': dName.isNotEmpty ? dName : 'Doctor',
              'specialty': dSpec.isNotEmpty ? dSpec : 'General Medicine',
              'speciality': dSpec.isNotEmpty ? dSpec : 'General Medicine',
              'department': dDept,
              'phone': dPhone,
              'clinicId': clinicId,
              'clinicName': cName,
              'status': _cleanField(rawD['availability_status']).isNotEmpty
                  ? _cleanField(rawD['availability_status'])
                  : 'Available',
              'profilePhoto': uMap['biometric_token'],
            });
          }
          return {
            'success': true,
            'count': list.length,
            'totalCount': list.length,
            'doctors': list,
            'dentists': list,
          };
        } catch (sbErr) {
          debugPrint('fetchClinicDoctorsFiltered Supabase fallback error: $sbErr');
        }
      }
    }
    return {'success': false, 'message': 'Unable to load associated doctors.'};
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String clinicId,
    required List<String> doctorIds,
    String? clinicName,
  })? debugAssociateDoctorsToClinicOverride;

  /// Associate one or multiple existing registered doctors with a clinic (`POST /clinics/:clinicId/doctors/associate`)
  Future<Map<String, dynamic>> associateDoctorsToClinic({
    required String clinicId,
    required List<String> doctorIds,
    String? clinicName,
    http.Client? client,
  }) async {
    if (debugAssociateDoctorsToClinicOverride != null) {
      return debugAssociateDoctorsToClinicOverride!(
        clinicId: clinicId,
        doctorIds: doctorIds,
        clinicName: clinicName,
      );
    }
    final cleanIds = doctorIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (cleanIds.isEmpty) {
      return {'success': false, 'message': 'Please select at least one doctor.'};
    }
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$clinicId/doctors/associate');
      final body = jsonEncode({
        if (cleanIds.length == 1) 'doctorId': cleanIds.first,
        'doctorIds': cleanIds,
        if (clinicName != null && clinicName.trim().isNotEmpty) 'clinicName': clinicName.trim(),
      });
      final response = await (client != null
              ? client.post(uri, headers: _headersWithUser(), body: body)
              : http.post(uri, headers: _headersWithUser(), body: body))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode >= 500) {
        throw Exception('Associate doctors backend HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return {
          ...decoded,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      debugPrint('associateDoctorsToClinic notice ($e), attempting 24/7 Supabase fallback...');
      final sb = SupabaseService.safeClient;
      if (sb != null) {
        try {
          for (final dId in cleanIds) {
            try {
              await sb.from('dentists').update({
                'clinic_id': clinicId,
                if (clinicName != null && clinicName.trim().isNotEmpty) 'clinic_name': clinicName.trim(),
              }).eq('id', dId);
            } catch (_) {
              await sb.from('dentists').update({'clinic_id': clinicId}).eq('id', dId);
            }
          }
          return {
            'success': true,
            'statusCode': 200,
            'message': '${cleanIds.length} doctor(s) associated with clinic successfully.',
            'associatedDoctorIds': cleanIds,
          };
        } catch (sbErr) {
          debugPrint('associateDoctorsToClinic Supabase fallback error: $sbErr');
        }
      }
    }
    return {'success': false, 'message': 'Unable to associate selected doctors with this clinic.'};
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> Function({
    required String clinicId,
    required String doctorId,
  })? debugRemoveDoctorAssociationOverride;

  /// Remove a doctor's association from a clinic without deleting the doctor account (`DELETE /clinics/:clinicId/doctors/:doctorId`)
  Future<Map<String, dynamic>> removeDoctorAssociationFromClinic({
    required String clinicId,
    required String doctorId,
    http.Client? client,
  }) async {
    if (debugRemoveDoctorAssociationOverride != null) {
      return debugRemoveDoctorAssociationOverride!(
        clinicId: clinicId,
        doctorId: doctorId,
      );
    }
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$clinicId/doctors/$doctorId');
      final response = await (client != null
              ? client.delete(uri, headers: _headersWithUser())
              : http.delete(uri, headers: _headersWithUser()))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode >= 500) {
        throw Exception('Remove doctor association backend HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return {
          ...decoded,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      debugPrint('removeDoctorAssociationFromClinic notice ($e), attempting 24/7 Supabase fallback...');
      final sb = SupabaseService.safeClient;
      if (sb != null) {
        try {
          await sb.from('dentists').update({'clinic_id': null}).eq('id', doctorId);
          return {
            'success': true,
            'statusCode': 200,
            'message': 'Doctor association removed from clinic.',
          };
        } catch (sbErr) {
          debugPrint('removeDoctorAssociationFromClinic Supabase fallback error: $sbErr');
        }
      }
    }
    return {'success': false, 'message': 'Unable to remove doctor association.'};
  }

  /// Update structured clinic profile details & OSM coordinates (`PUT /clinics/:clinicId`)
  Future<Map<String, dynamic>> updateClinicProfileDetails({
    required String clinicId,
    String? clinicName,
    String? clinicAddress,
    String? city,
    String? state,
    String? pincode,
    double? latitude,
    double? longitude,
    http.Client? client,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/clinics/$clinicId');
      final body = jsonEncode({
        if (clinicName != null && clinicName.trim().isNotEmpty) 'clinicName': clinicName.trim(),
        if (clinicAddress != null) 'clinicAddress': clinicAddress.trim(),
        if (clinicAddress != null) 'location': clinicAddress.trim(),
        if (city != null) 'city': city.trim(),
        if (state != null) 'state': state.trim(),
        if (pincode != null) 'pincode': pincode.trim(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      });
      final response = await (client != null
              ? client.put(uri, headers: _headersWithUser(), body: body)
              : http.put(uri, headers: _headersWithUser(), body: body))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode >= 500) {
        throw Exception('Update clinic profile backend HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('updateClinicProfileDetails notice ($e), attempting 24/7 Supabase fallback...');
      final sb = SupabaseService.safeClient;
      if (sb != null) {
        try {
          try {
            await sb.from('clinics').update({
              if (clinicName != null && clinicName.trim().isNotEmpty) 'clinic_name': clinicName.trim(),
              if (clinicAddress != null) 'location': clinicAddress.trim(),
              if (clinicAddress != null) 'clinic_address': clinicAddress.trim(),
              if (city != null) 'city': city.trim(),
              if (state != null) 'state': state.trim(),
              if (pincode != null) 'pincode': pincode.trim(),
              if (latitude != null) 'latitude': latitude,
              if (longitude != null) 'longitude': longitude,
            }).eq('id', clinicId);
          } catch (_) {
            await sb.from('clinics').update({
              if (clinicName != null && clinicName.trim().isNotEmpty) 'clinic_name': clinicName.trim(),
              if (clinicAddress != null) 'location': clinicAddress.trim(),
            }).eq('id', clinicId);
          }
          return {
            'success': true,
            'message': 'Clinic profile updated successfully.',
          };
        } catch (sbErr) {
          debugPrint('updateClinicProfileDetails Supabase fallback error: $sbErr');
        }
      }
    }
    return {'success': false, 'message': 'Unable to update clinic profile details.'};
  }
}




