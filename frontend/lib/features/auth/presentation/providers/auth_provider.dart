import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  AuthNotifier() : super(AuthState());

  // Simulate authentication register/login lifecycle
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    
    await Future.delayed(const Duration(seconds: 1)); // Network simulation

    if (email.contains('@') && password.length >= 6) {
      // Mock successful login
      state = state.copyWith(
        isLoading: false, 
        token: "mock-jwt-token-val-9293",
        role: "Patient"
      );
      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        error: "Invalid email structure or weak password."
      );
      return false;
    }
  }

  // Simulate Mobile OTP validation
  Future<bool> verifyMobileOTP(String phone, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    await Future.delayed(const Duration(milliseconds: 800));

    if (code == "8849") {
      state = state.copyWith(
        isLoading: false,
        token: "mock-jwt-token-val-otp",
        role: "Patient"
      );
      return true;
    } else {
      state = state.copyWith(isLoading: false, error: "Invalid verification code.");
      return false;
    }
  }

  void logout() {
    state = AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
