import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/firebase_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/services/supabase_service.dart';
import 'package:dentaguru/core/utils/record_file_helper.dart';
import 'package:dentaguru/core/widgets/whatsapp_chat_modal.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_profile_completion_screen.dart';
import 'package:dentaguru/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recordFilesChannel = MethodChannel('com.example.dentaguru/record_files');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionService().resetInMemoryCacheForTest();
    ApiService.debugFetchRealtimeTokenOverride = null;
    SupabaseService.debugOnRealtimeSetAuth = null;
    RecordFileHelper.testFilePickerOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordFilesChannel, null);
  });

  tearDown(() async {
    ApiService.debugFetchRealtimeTokenOverride = null;
    SupabaseService.debugOnRealtimeSetAuth = null;
    RecordFileHelper.testFilePickerOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordFilesChannel, null);
    await SessionService().clearSession();
  });

  group('Android Platform Parity & Native Bridges', () {
    test('FirebaseService aligns encryptedSharedPreferences and session token key and safely skips uninitialized sync', () async {
      expect(
        FirebaseService.secureStorageForTesting.aOptions.params['encryptedSharedPreferences'],
        equals('true'),
      );
      expect(
        FirebaseService.authTokenStorageKey,
        equals('dentaguru_secure_auth_token'),
      );

      // Should not throw when Firebase is uninitialized in unit tests
      await expectLater(
        FirebaseService.syncFcmTokenAfterLogin(authToken: 'test-jwt'),
        completes,
      );
    });

    test('Android record_files MethodChannel supports PDF picking and real save/open responses (no no-op stub)', () async {
      final pdfBytes = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]); // %PDF-1.4
      String? capturedSaveFileName;
      String? capturedSaveMime;
      int? capturedSaveLength;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recordFilesChannel, (MethodCall call) async {
        if (call.method == 'pickRecordFile') {
          return <String, dynamic>{
            'name': 'dental_xray_report.pdf',
            'mimeType': 'application/pdf',
            'bytes': pdfBytes,
            'sizeBytes': pdfBytes.length,
          };
        }
        if (call.method == 'saveAndOpenRecordFile') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          capturedSaveFileName = args['fileName']?.toString();
          capturedSaveMime = args['mimeType']?.toString();
          capturedSaveLength = (args['bytes'] as Uint8List).length;
          return true;
        }
        return null;
      });

      final picked = await RecordFileHelper.pickRecordFile();
      expect(picked, isNotNull);
      expect(picked!.name, 'dental_xray_report.pdf');
      expect(picked.isPdf, isTrue);
      expect(picked.mimeType, 'application/pdf');
      expect(picked.sizeBytes, pdfBytes.length);

      final saved = await RecordFileHelper.downloadRecordFile(
        bytes: pdfBytes,
        fileName: 'dental_xray_report.pdf',
        mimeType: 'application/pdf',
      );
      expect(saved, isTrue);
      expect(capturedSaveFileName, 'dental_xray_report.pdf');
      expect(capturedSaveMime, 'application/pdf');
      expect(capturedSaveLength, pdfBytes.length);

      // When native channel reports failure, helper returns false (never fake true)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recordFilesChannel, (MethodCall call) async {
        if (call.method == 'saveAndOpenRecordFile') {
          throw PlatformException(code: 'SAVE_ERROR', message: 'Disk full');
        }
        return null;
      });
      final failedSave = await RecordFileHelper.downloadRecordFile(
        bytes: pdfBytes,
        fileName: 'dental_xray_report.pdf',
        mimeType: 'application/pdf',
      );
      expect(failedSave, isFalse);
    });

    testWidgets('DentaGuruApp lifecycle resume rebinds Realtime JWT for Patients and preserves Sub-Admin restriction', (tester) async {
      int realtimeFetchCount = 0;
      ApiService.debugFetchRealtimeTokenOverride = () async {
        realtimeFetchCount++;
        return {
          'success': true,
          'realtimeToken': 'rt-jwt-$realtimeFetchCount',
          'realtimeTokenExpiresAt': DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
        };
      };
      SupabaseService.debugOnRealtimeSetAuth = (_) {};

      // 1. Patient session: saveSession fetches once (if token missing), lifecycle resume rebinds
      await SessionService().saveSession(
        token: 'patient-jwt',
        role: 'Patient',
        userId: 'pat-life-1',
        phone: '9876543210',
        realtimeToken: 'expired-rt',
        realtimeTokenExpiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final countAfterSave = realtimeFetchCount;
      // Expire cached realtimeToken so resume forces a refresh
      await SessionService().saveSession(
        token: 'patient-jwt',
        role: 'Patient',
        userId: 'pat-life-1',
        phone: '9876543210',
        realtimeToken: null,
        realtimeTokenExpiresAt: null,
      );
      final baselineCount = realtimeFetchCount;

      await tester.pumpWidget(const ProviderScope(child: DentaGuruApp()));
      await tester.pump();

      // Simulate expired realtime token in memory before resume
      SessionService().currentSession; // active session present
      // Replace with expired realtime token directly via clear + re-save without override then restore
      ApiService.debugFetchRealtimeTokenOverride = null;
      await SessionService().saveSession(
        token: 'patient-jwt',
        role: 'Patient',
        userId: 'pat-life-1',
        phone: '9876543210',
        realtimeToken: 'stale-rt',
        realtimeTokenExpiresAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      ApiService.debugFetchRealtimeTokenOverride = () async {
        realtimeFetchCount++;
        return {
          'success': true,
          'realtimeToken': 'rt-jwt-resumed-$realtimeFetchCount',
          'realtimeTokenExpiresAt': DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
        };
      };

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));

      expect(realtimeFetchCount, greaterThan(baselineCount));
      expect(countAfterSave, greaterThanOrEqualTo(1));

      // 2. Sub-Admin session: lifecycle resume MUST NOT fetch or bind Realtime JWT
      ApiService.debugFetchRealtimeTokenOverride = null;
      await SessionService().saveSession(
        token: 'subadmin-jwt',
        role: 'Sub-Admin',
        userId: 'sub-life-1',
        email: 'sub@gshealth.in',
        realtimeToken: null,
      );
      final subAdminBefore = realtimeFetchCount;
      ApiService.debugFetchRealtimeTokenOverride = () async {
        realtimeFetchCount++;
        return {'success': false, 'status': 403};
      };

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));

      expect(realtimeFetchCount, equals(subAdminBefore));
      SupabaseService().clearRealtimeAuth();
      // Drain splash navigation timer cleanly before test teardown
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('WhatsAppChatModal handles AppLifecycleState.resumed cleanly and PatientProfileCompletionScreen fits narrow Android keyboard viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
      });

      final service = PatientProblemService();
      service.currentPatient = PatientProfile(
        id: 'pat-kb-360',
        name: 'Aarav',
        phone: '9876543211',
        age: '',
        gender: '',
        pincode: '',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: PatientProfileCompletionScreen(serviceTitle: 'Book a Visit'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      // Verify WhatsAppChatModal lifecycle resume observer runs without exception
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: WhatsAppChatModal(
                patientName: 'Aarav',
                doctorName: 'Dr. Meera',
                currentUserRole: 'Patient',
                patientId: 'pat-kb-360',
                doctorId: 'doc-1',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}
