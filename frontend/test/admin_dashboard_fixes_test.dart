import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/widgets/dental_ads_banner.dart';
import 'package:dentaguru/core/widgets/whatsapp_chat_modal.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_profile_screen.dart';
import 'package:dentaguru/features/dentist/presentation/screens/doctor_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      return null;
    });
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchClinicsOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugFetchConversationsOverride = null;
    ApiService.debugFetchChatMessagesOverride = null;
    ApiService.debugSendMessageOverride = null;
    ApiService.debugToggleSubAdminStatusOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchClinicsOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugFetchConversationsOverride = null;
    ApiService.debugFetchChatMessagesOverride = null;
    ApiService.debugSendMessageOverride = null;
    ApiService.debugToggleSubAdminStatusOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  group('Admin Dashboard Complete Functionality Fixes', () {
    testWidgets('1. Revenue section is completely removed while preserving core admin stats', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Revenue'), findsNothing);
      expect(find.text('Revenue & Payments'), findsNothing);
      expect(find.text('Revenue & Financials'), findsNothing);
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Clinics Directory'), findsWidgets);
    });

    testWidgets('2. Chats panel & WhatsAppChatModal support conversations, unread badge, sending & error feedback', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storedMessages = <Map<String, dynamic>>[
        {
          'id': 'm-1',
          'room_id': 'CHAT_SATYA_ROHITHA',
          'sender_id': 'pat-1',
          'message': 'Good morning Doctor',
          'type': 'patient',
          'read': false,
          'created_at': '2026-11-19T08:00:00Z',
          'sender': {'id': 'pat-1', 'name': 'Satya', 'role': 'Patient'},
        },
      ];

      ApiService.debugFetchConversationsOverride = () async => [
            {
              'roomId': 'CHAT_SATYA_ROHITHA',
              'patientName': 'Satya',
              'doctorName': 'Dr. Rohitha',
              'lastMessage': 'Good morning Doctor',
              'totalMessages': 1,
              'unreadCount': 2,
              'lastMessageTime': '2026-11-19T08:00:00Z',
            },
          ];
      ApiService.debugFetchChatMessagesOverride = ({required String roomId}) async => List<dynamic>.from(storedMessages);
      ApiService.debugSendMessageOverride = ({
        required String senderId,
        required String message,
        required String roomId,
        String? receiverId,
        String? type,
        String? senderRole,
      }) async {
        final newMsg = {
          'id': 'm-${storedMessages.length + 1}',
          'room_id': roomId,
          'sender_id': senderId,
          'message': message,
          'type': type ?? 'text',
          'read': false,
          'created_at': DateTime.now().toIso8601String(),
          'sender': {'id': senderId, 'name': 'Satya', 'role': senderRole ?? 'Patient'},
        };
        storedMessages.add(newMsg);
        return {'success': true, 'chat': newMsg};
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen(initialTab: 10)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Satya'), findsWidgets);
      expect(find.text('2 unread'), findsOneWidget);

      // Test WhatsAppChatModal standalone send & persistence
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: WhatsAppChatModal(
                patientName: 'Satya',
                doctorName: 'Dr. Rohitha',
                currentUserRole: 'Patient',
                patientId: 'pat-1',
                doctorId: 'doc-1',
                roomIdOverride: 'CHAT_SATYA_ROHITHA',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Good morning Doctor'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'I have mild rash since yesterday');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('I have mild rash since yesterday'), findsOneWidget);
      expect(storedMessages.length, 2);

      // Verify send failure shows error banner
      ApiService.debugSendMessageOverride = ({
        required String senderId,
        required String message,
        required String roomId,
        String? receiverId,
        String? type,
        String? senderRole,
      }) async =>
          {'success': false, 'message': 'Permission denied for test'};

      await tester.enterText(find.byType(TextField), 'Should fail');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Permission denied for test'), findsWidgets);
    });

    testWidgets('3. Clinics modal shows Clinic ID, Email, Phone & real clinic doctors with availability', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      final clinicMap = {
        'id': 'clinic-devi-1',
        'clinic_name': 'Devi Multi-Specialty Clinic',
        'location': 'Kompally, Hyderabad',
        'phone': '8985732915',
        'email': 'devi@clinic.test',
        'services': ['Dermatology', 'Cardiology'],
      };
      final docMap = {
        'id': 'doc-rohitha-1',
        'user_id': 'u-rohitha-1',
        'clinic_id': 'clinic-devi-1',
        'name': 'Dr. Rohitha',
        'specialty': 'Dermatology',
        'qualification': 'MBBS, MD',
        'experienceYears': 7,
        'rating': 4.9,
        'reviews_count': 18,
        'clinicName': 'Devi Multi-Specialty Clinic',
        'phone': '8986754323',
        'email': 'rohitha@clinic.test',
        'availability_status': 'Unavailable',
        'consultation_fee': '₹600',
      };
      ApiService.debugFetchClinicsOverride = () async => [clinicMap];
      ApiService.debugFetchDentistsOverride = ({
        String? state,
        String? city,
        String? pincode,
        String? specialty,
        String? availability,
        String? language,
        List<String>? languages,
        String? search,
        bool includeUnavailable = false,
      }) async => [docMap];

      service.addTestClinic(ClinicModel.fromJson(clinicMap));
      service.addTestDoctor(DoctorModel.fromJson(docMap));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen(initialTab: 1)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Devi Multi-Specialty Clinic'), findsOneWidget);
      await tester.tap(find.text('Devi Multi-Specialty Clinic'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('clinic-devi-1'), findsWidgets);
      expect(find.textContaining('8985732915'), findsWidgets);
      expect(find.textContaining('devi@clinic.test'), findsWidgets);
      expect(find.text('Dr. Rohitha'), findsWidgets);
      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('ACTIVE'), findsNothing);
    });

    testWidgets('4. Zero hardcoded dummy clinic or doctor fallback strings on Doctor & Clinic profile screens', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: DoctorProfileScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.textContaining('Dr. Ananya Rao'), findsNothing);
      expect(find.textContaining('Bandra West Dental Clinic'), findsNothing);
      expect(find.textContaining('+919000000001'), findsNothing);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ClinicProfileScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.textContaining('Bandra West Dental Clinic'), findsNothing);
      expect(find.textContaining('Hill Road, Bandra West'), findsNothing);
    });

    testWidgets('5. Sub-Admin toggle respects backend persistence and reverts on error', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final saMap = {
        'id': 'sa-1',
        'name': 'Nikhil SubAdmin',
        'email': 'nikhil@gshealth.in',
        'phone': '9063663181',
        'status': 'ACTIVE',
        'permissions': ['PATIENT_VIEW'],
      };
      ApiService.debugFetchSubAdminsOverride = () async => [saMap];
      PatientProblemService().addTestSubAdminForTesting(saMap);

      ApiService.debugToggleSubAdminStatusOverride = (id, {status, isActive}) async => false;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen(initialTab: 9)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Nikhil SubAdmin'), findsOneWidget);
      expect(find.text('✓ Active'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pump(const Duration(milliseconds: 300));

      // Because backend returned false, UI must revert back to Active and display failure banner
      expect(find.text('✓ Active'), findsOneWidget);
      expect(find.textContaining('Failed to update'), findsOneWidget);
    });

    testWidgets('5b. Sub-Admin toggle persists INACTIVE/ACTIVE without auto-reversal and prevents duplicate calls', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final saState = {
        'id': 'sa-persist-1',
        'name': 'Surya SubAdmin',
        'email': 'surya@gshealth.in',
        'phone': '9492768737',
        'status': 'ACTIVE',
        'permissions': ['PATIENT_VIEW'],
      };
      int toggleCalls = 0;

      ApiService.debugFetchSubAdminsOverride = () async => [Map<String, dynamic>.from(saState)];
      PatientProblemService().addTestSubAdminForTesting(Map<String, dynamic>.from(saState));

      ApiService.debugToggleSubAdminStatusOverride = (id, {status, isActive}) async {
        toggleCalls++;
        await Future.delayed(const Duration(milliseconds: 80));
        saState['status'] = status ?? (isActive == true ? 'ACTIVE' : 'INACTIVE');
        return true;
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen(initialTab: 9)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Surya SubAdmin'), findsOneWidget);
      expect(find.text('✓ Active'), findsOneWidget);

      // Tap switch twice quickly; in-flight lock must allow only 1 API request
      await tester.tap(find.byType(Switch).first);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byType(Switch).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));

      expect(toggleCalls, 1);
      expect(find.text('⛔ Deactivated'), findsOneWidget);
      expect(find.text('✓ Active'), findsNothing);

      // Toggle back to ACTIVE
      await tester.tap(find.byType(Switch).first);
      await tester.pump(const Duration(milliseconds: 250));

      expect(toggleCalls, 2);
      expect(find.text('✓ Active'), findsOneWidget);
      expect(find.text('⛔ Deactivated'), findsNothing);
    });

    testWidgets('6. Devi clinic strictly shows only affiliated clinic doctors and no dummy ads/slots', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      expect(sponsoredAdsForAdmin(), isEmpty);

      final service = PatientProblemService();
      final deviClinicMap = {
        'id': 'clinic-devi-uuid',
        'user_id': 'user-devi-uuid',
        'clinic_name': 'devi clinic',
        'location': 'kompally',
        'phone': '8985732915',
        'email': 'devi@clinic.test',
        'services': ['Dermatology'],
      };
      final docRohithaMap = {
        'id': 'doc-rohitha',
        'user_id': 'u-rohitha',
        'clinic_id': 'clinic-devi-uuid',
        'name': 'Dr. rohitha',
        'specialty': 'Dermatology',
        'clinicName': 'devi clinic',
        'availability_status': 'Available',
      };
      final docSriMap = {
        'id': 'doc-sri',
        'user_id': 'u-sri',
        'clinic_id': '',
        'name': 'Dr. sri',
        'specialty': 'General Dentistry',
        'clinicName': '',
        'availability_status': 'Available',
      };
      final docSuryaMap = {
        'id': 'doc-surya',
        'user_id': 'u-surya',
        'clinic_id': '',
        'name': 'Dr. surya',
        'specialty': 'General Dentistry',
        'clinicName': '',
        'availability_status': 'Available',
      };
      final docOtherClinicMap = {
        'id': 'doc-other',
        'user_id': 'u-other',
        'clinic_id': 'clinic-other-uuid',
        'name': 'Dr. Other Clinic',
        'specialty': 'Cardiology',
        'clinicName': 'devi clinic',
        'availability_status': 'Available',
      };

      ApiService.debugFetchClinicsOverride = () async => [deviClinicMap];
      ApiService.debugFetchDentistsOverride = ({
        String? state,
        String? city,
        String? pincode,
        String? specialty,
        String? availability,
        String? language,
        List<String>? languages,
        String? search,
        bool includeUnavailable = false,
      }) async =>
          [docRohithaMap, docSriMap, docSuryaMap, docOtherClinicMap];

      final deviClinic = ClinicModel.fromJson(deviClinicMap);
      service.addTestClinic(deviClinic);
      service.addTestDoctor(DoctorModel.fromJson(docRohithaMap));
      service.addTestDoctor(DoctorModel.fromJson(docSriMap));
      service.addTestDoctor(DoctorModel.fromJson(docSuryaMap));
      service.addTestDoctor(DoctorModel.fromJson(docOtherClinicMap));

      expect(service.getDoctorsForClinic(deviClinic).map((d) => d.name).toList(), ['Dr. rohitha']);
      expect(service.getClinicDoctors(''), isEmpty);
      expect(service.getClinicDoctors('GS HEALTH Partner Clinic'), isEmpty);
      expect(service.getClinicDoctors('devi clinic').map((d) => d.name).toList(), ['Dr. rohitha']);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen(initialTab: 1)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 Clinic Doctor: Dr. rohitha'), findsOneWidget);
      expect(find.textContaining('Dr. sri'), findsNothing);
      expect(find.textContaining('Dr. surya'), findsNothing);
      expect(find.textContaining('Dr. Other Clinic'), findsNothing);
      expect(find.text('09:00 AM - 05:00 PM (30m)'), findsNothing);
    });
  });
}
