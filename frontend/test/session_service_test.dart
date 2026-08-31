import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentaguru/core/models/user_session.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('UserSession Model Tests', () {
    test('Correctly identifies targetRoute based on user role', () {
      final now = DateTime.now();

      final patientSession = UserSession(
        token: 'token_123',
        userId: 'pat_1',
        role: 'Patient',
        createdAt: now,
      );
      expect(patientSession.targetRoute, '/patient');
      expect(patientSession.displayRole, 'Patient');

      final dentistSession = UserSession(
        token: 'token_456',
        userId: 'doc_1',
        role: 'Dentist',
        createdAt: now,
      );
      expect(dentistSession.targetRoute, '/dentist');
      expect(dentistSession.displayRole, 'Dentist');

      final doctorSession = UserSession(
        token: 'token_456_b',
        userId: 'doc_2',
        role: 'Doctor Specialist',
        createdAt: now,
      );
      expect(doctorSession.targetRoute, '/dentist');
      expect(doctorSession.displayRole, 'Dentist');

      final adminSession = UserSession(
        token: 'token_789',
        userId: 'admin_1',
        role: 'Admin',
        createdAt: now,
      );
      expect(adminSession.targetRoute, '/admin');
      expect(adminSession.displayRole, 'Admin');

      final subAdminSession = UserSession(
        token: 'token_999',
        userId: 'subadmin_1',
        role: 'Sub-Admin',
        createdAt: now,
      );
      expect(subAdminSession.targetRoute, '/admin');
      expect(subAdminSession.displayRole, 'Sub-Admin');

      final clinicSession = UserSession(
        token: 'token_clinic',
        userId: 'clinic_1',
        role: 'Clinic',
        createdAt: now,
      );
      expect(clinicSession.targetRoute, '/clinic');
      expect(clinicSession.displayRole, 'Clinic');
    });

    test('Correctly determines session expiration state', () {
      final now = DateTime.now();

      final activeSession = UserSession(
        token: 'token_active',
        userId: 'user_1',
        role: 'Patient',
        createdAt: now,
        expiresAt: now.add(const Duration(days: 30)),
      );
      expect(activeSession.isExpired, isFalse);

      final expiredSession = UserSession(
        token: 'token_expired',
        userId: 'user_2',
        role: 'Patient',
        createdAt: now.subtract(const Duration(days: 40)),
        expiresAt: now.subtract(const Duration(days: 10)),
      );
      expect(expiredSession.isExpired, isTrue);

      final nonExpiringSession = UserSession(
        token: 'token_forever',
        userId: 'user_3',
        role: 'Dentist',
        createdAt: now,
        expiresAt: null,
      );
      expect(nonExpiringSession.isExpired, isFalse);
    });

    test('Serializes to and from JSON without loss of data', () {
      final now = DateTime.now();
      final original = UserSession(
        token: 'auth_jwt_token_sample',
        userId: 'usr_8823',
        role: 'Dentist',
        email: 'doctor@dentaguru.internal',
        phone: '+919876543210',
        name: 'Dr. John Doe',
        createdAt: now,
        expiresAt: now.add(const Duration(days: 30)),
        metadata: {
          'specialty': 'Orthodontics',
          'clinicName': 'Apex Smiles Clinic',
        },
      );

      final serialized = original.serialize();
      final deserialized = UserSession.deserialize(serialized);

      expect(deserialized, isNotNull);
      expect(deserialized!.token, 'auth_jwt_token_sample');
      expect(deserialized.userId, 'usr_8823');
      expect(deserialized.role, 'Dentist');
      expect(deserialized.email, 'doctor@dentaguru.internal');
      expect(deserialized.phone, '+919876543210');
      expect(deserialized.name, 'Dr. John Doe');
      expect(deserialized.metadata['specialty'], 'Orthodontics');
      expect(deserialized.metadata['clinicName'], 'Apex Smiles Clinic');
      expect(deserialized.targetRoute, '/dentist');
    });
  });

  group('SessionService Functional Tests', () {
    test('Saves, retrieves, and validates user session in secure storage', () async {
      final sessionService = SessionService();

      // Clear initially
      await sessionService.clearSession();
      expect(await sessionService.hasValidSession(), isFalse);

      // Save new persistent session
      final saved = await sessionService.saveSession(
        token: 'secure_auth_token_99',
        role: 'Patient',
        userId: 'patient_guid_123',
        email: 'patient@example.com',
        phone: '+919876500000',
        name: 'Jane Patient',
        metadata: {'city': 'Bangalore', 'pincode': '560001'},
      );

      expect(saved.token, 'secure_auth_token_99');
      expect(saved.role, 'Patient');

      // Verify retrieval
      final retrieved = await sessionService.getSession();
      expect(retrieved, isNotNull);
      expect(retrieved!.userId, 'patient_guid_123');
      expect(retrieved.email, 'patient@example.com');
      expect(retrieved.name, 'Jane Patient');
      expect(retrieved.targetRoute, '/patient');

      // Verify active API service token assignment
      expect(ApiService().currentToken, 'secure_auth_token_99');
      expect(await sessionService.hasValidSession(), isTrue);

      // Update session user metadata
      await sessionService.updateSessionUser(
        name: 'Jane Patient Updated',
        additionalMetadata: {'bloodGroup': 'A+'},
      );

      final updated = await sessionService.getSession();
      expect(updated!.name, 'Jane Patient Updated');
      expect(updated.metadata['bloodGroup'], 'A+');
      expect(updated.metadata['city'], 'Bangalore');

      // Clear session on logout
      await sessionService.clearSession();
      expect(await sessionService.getSession(), isNull);
      expect(await sessionService.hasValidSession(), isFalse);
      expect(ApiService().currentToken, isNull);
    });
  });
}
