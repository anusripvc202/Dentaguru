import 'dart:convert';

/// Model representing an authenticated user session in DentaGuru.
class UserSession {
  final String token;
  final String userId;
  final String role;
  final String? email;
  final String? phone;
  final String? name;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? realtimeToken;
  final DateTime? realtimeTokenExpiresAt;
  final Map<String, dynamic> metadata;

  const UserSession({
    required this.token,
    required this.userId,
    required this.role,
    this.email,
    this.phone,
    this.name,
    required this.createdAt,
    this.expiresAt,
    this.realtimeToken,
    this.realtimeTokenExpiresAt,
    this.metadata = const {},
  });

  /// Canonical `public.users.id` across all roles (resolves Doctor dual-ID where `userId` may hold `dentists.id`).
  String get canonicalUserId {
    final accountId = (metadata['accountUserId'] ?? metadata['userId'] ?? '').toString().trim();
    if (accountId.isNotEmpty) return accountId;
    return userId.trim();
  }

  /// Optional `public.dentists.id` for Doctor accounts.
  String? get dentistId {
    final dId = (metadata['dentistId'] ?? '').toString().trim();
    if (dId.isNotEmpty) return dId;
    final norm = role.trim().toLowerCase();
    if (norm.contains('dentist') || norm.contains('doctor')) {
      return userId.trim().isNotEmpty ? userId.trim() : null;
    }
    return null;
  }

  /// Optional `public.clinics.id` for Clinic or Clinic-affiliated Doctor accounts.
  String? get clinicId {
    final cId = (metadata['clinicId'] ?? metadata['clinic_id'] ?? '').toString().trim();
    return cId.isNotEmpty ? cId : null;
  }

  /// Returns true when a non-expired Supabase Realtime JWT is present (with safety margin before expiry).
  bool hasValidRealtimeToken({Duration minRemaining = const Duration(seconds: 90)}) {
    final rt = (realtimeToken ?? '').trim();
    if (rt.isEmpty) return false;
    if (realtimeTokenExpiresAt == null) return true;
    return DateTime.now().add(minRemaining).isBefore(realtimeTokenExpiresAt!);
  }

  /// Check if the saved session has exceeded its expiration threshold
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Get the appropriate dashboard route for this user role
  String get targetRoute {
    final normalized = role.trim().toLowerCase();
    if (normalized.contains('dentist') || normalized.contains('doctor')) {
      return '/dentist';
    }
    if (normalized.contains('clinic')) {
      return '/clinic';
    }
    if (normalized.contains('sub-admin') || normalized.contains('subadmin') || normalized.contains('sub_admin')) {
      return '/sub-admin';
    }
    if (normalized.contains('admin')) {
      return '/admin';
    }
    return '/patient';
  }

  /// Normalized role display title
  String get displayRole {
    final normalized = role.trim().toLowerCase();
    if (normalized.contains('dentist') || normalized.contains('doctor')) {
      return 'Doctor';
    }
    if (normalized.contains('clinic')) {
      return 'Clinic';
    }
    if (normalized.contains('sub-admin') || normalized.contains('subadmin') || normalized.contains('sub_admin')) {
      return 'Sub-Admin';
    }
    if (normalized.contains('admin')) {
      return 'Admin';
    }
    return 'Patient';
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'userId': userId,
      'role': role,
      'email': email,
      'phone': phone,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      if (realtimeToken != null) 'realtimeToken': realtimeToken,
      if (realtimeTokenExpiresAt != null) 'realtimeTokenExpiresAt': realtimeTokenExpiresAt!.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      token: (json['token'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      role: (json['role'] ?? 'Patient').toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      name: json['name']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      realtimeToken: json['realtimeToken']?.toString(),
      realtimeTokenExpiresAt: json['realtimeTokenExpiresAt'] != null
          ? DateTime.tryParse(json['realtimeTokenExpiresAt'].toString())
          : null,
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'])
          : {},
    );
  }

  String serialize() => jsonEncode(toJson());

  static UserSession? deserialize(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return null;
    try {
      final map = jsonDecode(rawJson);
      if (map is Map<String, dynamic>) {
        return UserSession.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  UserSession copyWith({
    String? token,
    String? userId,
    String? role,
    String? email,
    String? phone,
    String? name,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? realtimeToken,
    DateTime? realtimeTokenExpiresAt,
    Map<String, dynamic>? metadata,
  }) {
    return UserSession(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      realtimeToken: realtimeToken ?? this.realtimeToken,
      realtimeTokenExpiresAt: realtimeTokenExpiresAt ?? this.realtimeTokenExpiresAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
