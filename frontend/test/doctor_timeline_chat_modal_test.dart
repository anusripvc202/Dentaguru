import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/core/widgets/whatsapp_chat_modal.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  DoctorModel makeDoctor({
    String id = 'doc-chat-1',
    String name = 'Dr. Priya Nair',
  }) {
    return DoctorModel(
      id: id,
      userId: 'user-$id',
      name: name,
      specialty: 'Cardiology',
      qualification: 'MBBS, MD',
      experienceYears: 9,
      rating: 4.8,
      reviewCount: 25,
      clinicName: 'GS Heart Clinic',
      clinicAddress: 'Banjara Hills, Hyderabad',
      phone: '9876543210',
      email: 'priya@gshealth.test',
      status: 'Available',
      verificationStatus: 'VERIFIED',
      nextAvailableSlots: const ['10:00 AM', '10:30 AM'],
      consultationFee: '₹700',
      city: 'Hyderabad',
      state: 'Telangana',
      pincode: '500034',
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async => null);
    BookingRulesConfig.debugNowOverride = DateTime(2026, 11, 26, 8, 0);
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchClinicsOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugFetchChatMessagesOverride = null;
    ApiService.debugSendMessageOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    BookingRulesConfig.debugNowOverride = null;
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchClinicsOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
    ApiService.debugFetchChatMessagesOverride = null;
    ApiService.debugSendMessageOverride = null;
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  testWidgets(
    'DentistTimelineScreen Chat button passes patientId and roomIdOverride to WhatsAppChatModal and sends receiverId',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      final doc = makeDoctor();
      service.addTestDoctor(doc);
      service.currentDoctor = doc;

      final today = DateTime.now();
      final ymd =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      service.addTestRequest(
        PatientConsultationRequest(
          id: 'appt-chat-1',
          patientId: 'pat-uuid-123',
          patientName: 'Ananya Verma',
          patientPhone: '9876500001',
          problemCategory: 'Cardiology',
          problemDescription: 'Follow-up ECG review',
          severity: 'Moderate',
          submittedAt: today,
          status: 'CONFIRMED',
          assignedDoctorId: doc.id,
          assignedDoctorName: doc.name,
          consultationMode: 'Online',
          confirmedDate: ymd,
          confirmedTimeSlot: '10:00 AM',
        ),
      );

      String? fetchedRoomId;
      Map<String, dynamic>? sentPayload;

      ApiService.debugFetchChatMessagesOverride = ({required String roomId}) async {
        fetchedRoomId = roomId;
        return [];
      };
      ApiService.debugSendMessageOverride = ({
        required String senderId,
        required String message,
        required String roomId,
        String? receiverId,
        String? type,
        String? senderRole,
      }) async {
        sentPayload = {
          'senderId': senderId,
          'message': message,
          'roomId': roomId,
          'receiverId': receiverId,
          'type': type,
          'senderRole': senderRole,
        };
        return {'success': true};
      };

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: DentistTimelineScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final chatBtn = find.widgetWithText(OutlinedButton, 'Chat').first;
      await tester.ensureVisible(chatBtn);
      await tester.pump();
      await tester.tap(chatBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final modal = tester.widget<WhatsAppChatModal>(find.byType(WhatsAppChatModal));
      final expectedRoomId = ApiService.getChatRoomId(
        patientIdOrName: 'Ananya Verma',
        dentistIdOrName: doc.name,
      );

      expect(modal.patientId, 'pat-uuid-123');
      expect(modal.doctorId, doc.id);
      expect(modal.doctorName, doc.name);
      expect(modal.roomIdOverride, expectedRoomId);
      expect(fetchedRoomId, expectedRoomId);

      await tester.enterText(find.byType(TextField).last, 'Hello Ananya, please join.');
      final sendBtn = find.byIcon(Icons.send_rounded);
      await tester.ensureVisible(sendBtn);
      await tester.pump();
      await tester.tap(sendBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(sentPayload, isNotNull);
      expect(sentPayload!['receiverId'], 'pat-uuid-123');
      expect(sentPayload!['roomId'], expectedRoomId);
      expect(sentPayload!['senderRole'], 'Dentist');
    },
  );
}
