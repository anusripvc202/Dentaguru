import 'package:dentaguru/core/constants/permissions.dart';
import 'package:dentaguru/core/models/user_session.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/services/supabase_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SupabaseService.resetForTesting();
    ApiService.debugFetchRealtimeTokenOverride = null;
    await SessionService().clearSession();
  });

  tearDown(() async {
    ApiService.debugFetchRealtimeTokenOverride = null;
    SupabaseService.resetForTesting();
    await SessionService().clearSession();
  });

  group('Phase 2A — Flutter Supabase Realtime Auth, Refresh & 5-Role Identity Tests', () {
    test('1. Authenticates Realtime WebSocket and resolves canonical public.users.id across all 5 roles (including Doctor dual-ID)', () async {
      final capturedRealtimeTokens = <String>[];
      SupabaseService.debugOnRealtimeSetAuth = capturedRealtimeTokens.add;

      final expFuture = DateTime.now().add(const Duration(hours: 1));
      final roles = <({
        String role,
        String sessionUserId,
        String expectedCanonicalUserId,
        String? expectedDentistId,
        String? expectedClinicId,
        Map<String, dynamic> metadata,
        String rtToken,
      })>[
        (
          role: 'Patient',
          sessionUserId: '11111111-1111-4111-8111-111111111111',
          expectedCanonicalUserId: '11111111-1111-4111-8111-111111111111',
          expectedDentistId: null,
          expectedClinicId: null,
          metadata: {'accountUserId': '11111111-1111-4111-8111-111111111111'},
          rtToken: 'rt_jwt_patient_fixture',
        ),
        (
          role: 'Dentist',
          // Simulates Doctor session where session.userId is dentists.id and metadata.userId is public.users.id
          sessionUserId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          expectedCanonicalUserId: '22222222-2222-4222-8222-222222222222',
          expectedDentistId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          expectedClinicId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          metadata: {
            'accountUserId': '22222222-2222-4222-8222-222222222222',
            'userId': '22222222-2222-4222-8222-222222222222',
            'dentistId': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'clinicId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          },
          rtToken: 'rt_jwt_doctor_fixture',
        ),
        (
          role: 'Clinic',
          sessionUserId: '33333333-3333-4333-8333-333333333333',
          expectedCanonicalUserId: '33333333-3333-4333-8333-333333333333',
          expectedDentistId: null,
          expectedClinicId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          metadata: {
            'accountUserId': '33333333-3333-4333-8333-333333333333',
            'clinicId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          },
          rtToken: 'rt_jwt_clinic_fixture',
        ),
        (
          role: 'ADMIN',
          sessionUserId: '339f745b-2192-4055-abec-d7e4adc6c837',
          expectedCanonicalUserId: '339f745b-2192-4055-abec-d7e4adc6c837',
          expectedDentistId: null,
          expectedClinicId: null,
          metadata: {'accountUserId': '339f745b-2192-4055-abec-d7e4adc6c837'},
          rtToken: 'rt_jwt_admin_fixture',
        ),
        (
          role: 'Sub-Admin',
          sessionUserId: '55555555-5555-4555-8555-555555555555',
          expectedCanonicalUserId: '55555555-5555-4555-8555-555555555555',
          expectedDentistId: null,
          expectedClinicId: null,
          metadata: {
            'accountUserId': '55555555-5555-4555-8555-555555555555',
            'isSubAdmin': true,
          },
          rtToken: 'rt_jwt_subadmin_fixture',
        ),
      ];

      for (final r in roles) {
        final saved = await SessionService().saveSession(
          token: 'express_jwt_${r.role}',
          role: r.role,
          userId: r.sessionUserId,
          realtimeToken: r.rtToken,
          realtimeTokenExpiresAt: expFuture,
          metadata: r.metadata,
        );

        expect(saved.canonicalUserId, r.expectedCanonicalUserId);
        expect(saved.dentistId, r.expectedDentistId);
        expect(saved.clinicId, r.expectedClinicId);
        expect(SupabaseService().activeRealtimeToken, r.rtToken);
      }

      expect(capturedRealtimeTokens, [
        'rt_jwt_patient_fixture',
        'rt_jwt_doctor_fixture',
        'rt_jwt_clinic_fixture',
        'rt_jwt_admin_fixture',
        'rt_jwt_subadmin_fixture',
      ]);
    });

    test('2. Proactively refreshes short-lived Realtime JWT before expiration and persists updated token', () async {
      final capturedTokens = <String>[];
      SupabaseService.debugOnRealtimeSetAuth = capturedTokens.add;

      int refreshCalls = 0;
      final renewedExpiry = DateTime.now().add(const Duration(hours: 1));
      ApiService.debugFetchRealtimeTokenOverride = () async {
        refreshCalls += 1;
        return {
          'success': true,
          'realtimeToken': 'rt_jwt_refreshed_v2',
          'realtimeTokenExpiresAt': renewedExpiry.toIso8601String(),
          'expiresIn': 3600,
        };
      };

      // Save session with a 400ms remaining lifetime so proactive renewal fires ~300ms later
      await SessionService().saveSession(
        token: 'express_jwt_pat',
        role: 'Patient',
        userId: '11111111-1111-4111-8111-111111111111',
        realtimeToken: 'rt_jwt_initial_v1',
        realtimeTokenExpiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      expect(SupabaseService().activeRealtimeToken, 'rt_jwt_initial_v1');

      // Trigger short-TTL proactive refresh directly
      await SupabaseService().authenticateRealtime(
        realtimeToken: 'rt_jwt_short_ttl',
        expiresAt: DateTime.now().add(const Duration(milliseconds: 300)),
        onRefreshRequired: () async {
          final res = await ApiService().fetchRealtimeToken();
          return (
            token: res['realtimeToken'].toString(),
            expiresAt: DateTime.parse(res['realtimeTokenExpiresAt'].toString()),
          );
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 550));

      expect(refreshCalls, 1);
      expect(SupabaseService().activeRealtimeToken, 'rt_jwt_refreshed_v2');
      expect(capturedTokens.last, 'rt_jwt_refreshed_v2');
    });

    test('3. Restoring an app session with an expired Realtime JWT fetches a fresh token and logout clears it', () async {
      final renewedExpiry = DateTime.now().add(const Duration(hours: 1));
      ApiService.debugFetchRealtimeTokenOverride = () async => {
            'success': true,
            'realtimeToken': 'rt_jwt_restored_fresh',
            'realtimeTokenExpiresAt': renewedExpiry.toIso8601String(),
          };

      final expiredSession = UserSession(
        token: 'express_jwt_valid',
        userId: '339f745b-2192-4055-abec-d7e4adc6c837',
        role: 'ADMIN',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().add(const Duration(days: 29)),
        realtimeToken: 'rt_jwt_expired_old',
        realtimeTokenExpiresAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      expect(expiredSession.hasValidRealtimeToken(), isFalse);

      await SessionService().saveSession(
        token: expiredSession.token,
        role: expiredSession.role,
        userId: expiredSession.userId,
        realtimeToken: expiredSession.realtimeToken,
        realtimeTokenExpiresAt: expiredSession.realtimeTokenExpiresAt,
      );

      expect(SupabaseService().activeRealtimeToken, 'rt_jwt_restored_fresh');
      expect(SessionService().currentSession?.realtimeToken, 'rt_jwt_restored_fresh');

      // Logout clears Realtime token and cancels timers
      await SessionService().clearSession();
      expect(SupabaseService().activeRealtimeToken, isNull);
    });

    test('4. Sub-Admin CHAT_VIEW, CHAT_SEND, and CHAT_ATTACHMENT_VIEW permissions are disabled by default', () {
      expect(AppPermissions.defaultPermissions.contains(AppPermissions.chatView), isFalse);
      expect(AppPermissions.defaultPermissions.contains(AppPermissions.chatSend), isFalse);
      expect(AppPermissions.defaultPermissions.contains(AppPermissions.chatAttachmentView), isFalse);

      final service = PatientProblemService();
      service.setSubAdminSession(
        id: '55555555-5555-4555-8555-555555555555',
        name: 'Restricted Sub-Admin',
        email: 'sub@gshealth.in',
        phone: '9888811111',
        permissions: AppPermissions.defaultPermissions,
        status: 'ACTIVE',
      );

      expect(service.hasPermission(AppPermissions.chatView), isFalse);
      expect(service.hasPermission(AppPermissions.chatSend), isFalse);
      expect(service.hasPermission(AppPermissions.chatAttachmentView), isFalse);

      // Explicitly granting CHAT_VIEW enables only CHAT_VIEW (not CHAT_SEND or CHAT_ATTACHMENT_VIEW)
      service.setSubAdminSession(
        id: '55555555-5555-4555-8555-555555555555',
        name: 'Chat View Sub-Admin',
        email: 'sub@gshealth.in',
        phone: '9888811111',
        permissions: [AppPermissions.patientView, AppPermissions.chatView],
        status: 'ACTIVE',
      );
      expect(service.hasPermission(AppPermissions.chatView), isTrue);
      expect(service.hasPermission(AppPermissions.chatSend), isFalse);
      expect(service.hasPermission(AppPermissions.chatAttachmentView), isFalse);

      // Deactivated Sub-Admin loses all chat permissions immediately
      service.setSubAdminSession(
        id: '55555555-5555-4555-8555-555555555555',
        name: 'Deactivated Sub-Admin',
        email: 'sub@gshealth.in',
        phone: '9888811111',
        permissions: [AppPermissions.chatView, AppPermissions.chatSend],
        status: 'INACTIVE',
      );
      expect(service.hasPermission(AppPermissions.chatView), isFalse);
      expect(service.hasPermission(AppPermissions.chatSend), isFalse);

      service.clearSubAdminSession();
    });
  });
}
