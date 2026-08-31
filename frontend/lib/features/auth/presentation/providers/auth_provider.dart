import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/session_service.dart';

class AuthState {
  final bool isLoading;
  final String? token;
  final String? role;
  final String? error;

  AuthState({this.isLoading = false, this.token, this.role, this.error});

  AuthState copyWith({
    bool? isLoading,
    String? token,
    String? role,
    String? error,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      role: role ?? this.role,
      error: error ?? this.error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    _loadInitialSession();
  }

  Future<void> _loadInitialSession() async {
    final session = await SessionService().getSession();
    if (session != null && !session.isExpired) {
      state = state.copyWith(
        token: session.token,
        role: session.role,
      );
    }
  }

  /// Login directly against Vercel live backend
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.login),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final token = (data['accessToken'] ?? 'sb_token_${data['user']?['id']}').toString();
        final role = data['user']?['role'] as String? ?? 'Patient';
        final userId = (data['user']?['id'] ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();
        final name = data['user']?['name'] as String?;

        await SessionService().saveSession(
          token: token,
          role: role,
          userId: userId,
          email: email,
          name: name,
          metadata: data['user'] is Map<String, dynamic> ? data['user'] : {},
        );

        state = state.copyWith(isLoading: false, token: token, role: role);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: data['message'] ?? 'Login failed. Invalid credentials.',
        );
        return false;
      }
    } catch (e) {
      debugPrint('Live Login Error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Unable to connect to Vercel cloud server.',
      );
      return false;
    }
  }

  /// Register user directly on Vercel live backend
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    String role = 'Patient',
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.register),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'role': role,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        final token = (data['accessToken'] ?? 'sb_token_${data['user']?['id']}').toString();
        final userId = (data['user']?['id'] ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();

        await SessionService().saveSession(
          token: token,
          role: role,
          userId: userId,
          email: email,
          phone: phone,
          name: name,
          metadata: data['user'] is Map<String, dynamic> ? data['user'] : {},
        );

        state = state.copyWith(isLoading: false, token: token, role: role);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: data['message'] ?? 'Registration failed.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Network error connecting to Vercel backend.',
      );
      return false;
    }
  }

  /// Verify Mobile OTP on Vercel API
  Future<bool> verifyMobileOTP(String phone, String code) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.verifyOtp),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final token = (data['accessToken'] ?? 'sb_token_${data['user']?['id']}').toString();
        final role = data['user']?['role'] as String? ?? 'Patient';
        final userId = (data['user']?['id'] ?? 'user_${DateTime.now().millisecondsSinceEpoch}').toString();
        final name = data['user']?['name'] as String?;
        final email = data['user']?['email'] as String?;

        await SessionService().saveSession(
          token: token,
          role: role,
          userId: userId,
          email: email,
          phone: phone,
          name: name,
          metadata: data['user'] is Map<String, dynamic> ? data['user'] : {},
        );

        state = state.copyWith(
          isLoading: false,
          token: token,
          role: role,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: data['message'] ?? 'Invalid verification code.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'OTP verification network error.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await SessionService().clearSession();
    state = AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
