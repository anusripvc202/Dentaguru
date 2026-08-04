import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _authToken;

  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Register a new user (Patient, Dentist, Clinic, Admin) in Supabase via Backend API
  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String password,
    required String phone,
    String role = 'Patient',
    String? specialty,
    String? licenseNumber,
    String? clinicName,
    String? clinicAddress,
    String? profilePhoto,
  }) async {
    try {
      final url = Uri.parse(ApiConstants.register);
      debugPrint('🌐 Sending Register Request to: $url');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'role': role,
          if (specialty != null) 'specialty': specialty,
          if (licenseNumber != null) 'licenseNumber': licenseNumber,
          if (clinicName != null) 'clinicName': clinicName,
          if (clinicAddress != null) 'clinicAddress': clinicAddress,
          if (profilePhoto != null) 'profilePhoto': profilePhoto,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['accessToken'] != null) {
          setAuthToken(data['accessToken']);
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Registration failed.'};
      }
    } catch (e) {
      debugPrint('❌ API Register Error: $e');
      return {'success': false, 'message': 'Could not connect to backend server.'};
    }
  }

  /// Login user via Backend API
  Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final url = Uri.parse(ApiConstants.login);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (data['accessToken'] != null) {
          setAuthToken(data['accessToken']);
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed.'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Could not connect to backend server.'};
    }
  }

  /// Fetch live dentists directory from Supabase
  Future<List<dynamic>> fetchDentists() async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}/dentists');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['dentists'] ?? [];
      }
    } catch (e) {
      debugPrint('Fetch dentists error: $e');
    }
    return [];
  }

  /// Fetch live clinics directory from Supabase
  Future<List<dynamic>> fetchClinics() async {
    try {
      final url = Uri.parse(ApiConstants.clinics);
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['clinics'] ?? [];
      }
    } catch (e) {
      debugPrint('Fetch clinics error: $e');
    }
    return [];
  }

  /// Create a new appointment in Supabase
  Future<Map<String, dynamic>> createAppointment({
    required String patientId,
    required String dentistId,
    required String clinicId,
    required String date,
    required String timeSlot,
    required String treatment,
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
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to create appointment.'};
    }
  }
}
