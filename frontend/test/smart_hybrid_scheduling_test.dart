import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';
import 'package:dentaguru/features/admin/presentation/widgets/doctor_slot_management_dialog.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/patient/presentation/widgets/appointment_management_dialog.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  DoctorModel makeDoctor({
    String id = 'doc-hybrid-1',
    String name = 'Dr. Hybrid Specialist',
    String status = 'Available',
  }) {
    return DoctorModel(
      id: id,
      userId: 'user-$id',
      name: name,
      specialty: 'Cardiology',
      qualification: 'MBBS, MD, DM',
      experienceYears: 11,
      rating: 4.9,
      reviewCount: 40,
      clinicName: 'GS Heart Center',
      clinicAddress: 'Banjara Hills, Hyderabad',
      phone: '9876543210',
      email: '$id@gshealth.test',
      status: status,
      verificationStatus: 'VERIFIED',
      nextAvailableSlots: const [
        '09:00 AM',
        '09:30 AM',
        '10:00 AM',
        '10:30 AM',
        '11:00 AM',
        '11:30 AM',
      ],
      consultationFee: '₹800',
      city: 'Hyderabad',
      state: 'Telangana',
      pincode: '500034',
    );
  }

  String ymd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async => null);
    BookingRulesConfig.applyFromJson({
      'inPersonDurationMinutes': 30,
      'onlineDurationMinutes': 20,
      'inPersonBufferMinutes': 10,
      'onlineBufferMinutes': 5,
      'minAdvanceBookingMinutes': 30,
      'defaultSlotIntervalMinutes': 30,
      'maxAdvanceBookingDays': 90,
      'adminDelayAlertThresholdMinutes': 15,
      'timezone': 'Asia/Kolkata',
    });
    BookingRulesConfig.debugNowOverride = DateTime(2026, 11, 25, 8, 0);
    ApiService.debugAdminAppointmentsOverride = null;
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchClinicsOverride = null;
    ApiService.debugFetchDentistsOverride = null;
    ApiService.debugFetchSubAdminsOverride = null;
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
    await SessionService().clearSession();
    await PatientProblemService().clearAllData();
  });

  group('BookingRulesConfig Hybrid Buffer & Conflict Logic', () {
    test('In-Person 10:00 AM (30m + 10m buffer) blocks 10:30 AM Online slot', () {
      final res = BookingRulesConfig.computeHybridAvailableSlots(
        date: DateTime(2026, 11, 26),
        slots: const ['09:30 AM', '10:00 AM', '10:30 AM', '11:00 AM'],
        consultationMode: 'Online',
        occupiedIntervals: const [
          {'startMin': 600, 'occupiedEndMin': 640}, // 10:00 AM + 30m + 10m = 10:40 AM
        ],
      );
      expect(res.contains('09:30 AM'), isTrue);
      expect(res.contains('10:00 AM'), isFalse);
      expect(res.contains('10:30 AM'), isFalse); // Overlaps 10:00-10:40 buffer
      expect(res.contains('11:00 AM'), isTrue);
    });

    test('Online -> In-Person respects 15m interval != 20m duration + 5m buffer', () {
      BookingRulesConfig.applyFromJson({'defaultSlotIntervalMinutes': 15});
      final res = BookingRulesConfig.computeHybridAvailableSlots(
        date: DateTime(2026, 11, 26),
        slots: const ['10:00 AM', '10:15 AM', '10:30 AM', '11:00 AM'],
        consultationMode: 'In-Person',
        occupiedIntervals: const [
          {'startMin': 600, 'occupiedEndMin': 625}, // 10:00 AM Online (20m + 5m buf = 10:25 AM)
        ],
      );
      expect(res.contains('10:00 AM'), isFalse);
      expect(res.contains('10:15 AM'), isFalse);
      expect(res.contains('10:30 AM'), isTrue);
    });

    test('Max advance booking window rejects dates beyond 90 days', () {
      final within = DateTime(2026, 11, 28);
      final beyond = DateTime(2027, 4, 1);
      expect(BookingRulesConfig.isSlotBookableForDate(within, '10:00 AM'), isTrue);
      expect(BookingRulesConfig.isSlotBookableForDate(beyond, '10:00 AM'), isFalse);
    });
  });

  group('Patient Hybrid Booking & Delay Response UI', () {
    testWidgets('BookVisitFlowDialog shows hybrid duration & buffer hint when toggling mode', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      final doc = makeDoctor();
      service.addTestDoctor(doc);
      service.currentPatient = PatientProfile(
        id: 'pat-hybrid-1',
        name: 'Test Patient',
        phone: '9888777666',
      );
      final targetDate = DateTime.now().add(const Duration(days: 2));
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'appt-inperson-1',
          patientId: 'other-pat',
          patientName: 'Other Patient',
          patientPhone: '9000000001',
          problemCategory: 'Cardiology',
          problemDescription: 'Existing In-Person',
          severity: 'Moderate',
          submittedAt: DateTime.now(),
          status: 'CONFIRMED',
          assignedDoctorId: doc.id,
          assignedDoctorName: doc.name,
          consultationMode: 'In-Person',
          durationMinutes: 30,
          bufferMinutes: 10,
          confirmedDate: ymd(targetDate),
          confirmedTimeSlot: '10:00 AM',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => BookVisitFlowDialog.show(ctx),
                  child: const Text('Open Booking'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Booking'));
      await tester.pumpAndSettle();

      // Step 1 -> select doctor -> Step 2 (Date, Time & Mode)
      await tester.tap(find.text('Dr. Hybrid Specialist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next: Select Date & Time'));
      await tester.pumpAndSettle();

      // Switch to Online Video mode via key
      await tester.tap(find.byKey(const Key('booking_mode_online')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('booking_hybrid_duration_hint')), findsOneWidget);
      expect(find.textContaining('20 mins (+5m buffer)'), findsOneWidget);
    });

    testWidgets('AppointmentManagementDialog renders delay notice with Wait / Reschedule / Switch actions', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final appt = PatientConsultationRequest(
        id: 'appt-delayed-ui',
        patientId: 'pat-1',
        patientName: 'Riya Patient',
        patientPhone: '9111222333',
        problemCategory: 'Cardiology',
        problemDescription: 'Follow-up consult',
        severity: 'Moderate',
        submittedAt: DateTime.now(),
        status: 'DELAYED',
        assignedDoctorId: 'doc-1',
        assignedDoctorName: 'Dr. Hybrid Specialist',
        consultationMode: 'Online',
        confirmedDate: ymd(tomorrow),
        confirmedTimeSlot: '10:30 AM',
        delayMinutes: 15,
        estimatedStartTime: '10:45 AM',
      );
      PatientProblemService().addTestRequest(appt);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AppointmentManagementDialog(appointment: appt),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appointment_delay_notice_card')), findsOneWidget);
      expect(find.textContaining('running ~15m late'), findsOneWidget);
      expect(find.textContaining('10:45 AM'), findsOneWidget);
      expect(find.byKey(const Key('delay_action_wait_btn')), findsOneWidget);
      expect(find.byKey(const Key('delay_action_request_reschedule_btn')), findsOneWidget);
      expect(find.byKey(const Key('delay_action_switch_doctor_btn')), findsOneWidget);
    });
  });

  group('Doctor & Admin Hybrid Scheduling Dashboards', () {
    testWidgets('DentistTimelineScreen shows hybrid status chips, Online/In-Person badges & lifecycle actions', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      final doc = makeDoctor();
      service.addTestDoctor(doc);
      service.currentDoctor = doc;

      final today = DateTime.now();
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'doc-appt-1',
          patientId: 'p1',
          patientName: 'Ananya Verma',
          patientPhone: '9876500001',
          problemCategory: 'Cardiology',
          problemDescription: 'ECG Review',
          severity: 'Moderate',
          submittedAt: today,
          status: 'CONFIRMED',
          assignedDoctorId: doc.id,
          assignedDoctorName: doc.name,
          consultationMode: 'Online',
          durationMinutes: 20,
          bufferMinutes: 5,
          confirmedDate: ymd(today),
          confirmedTimeSlot: '10:00 AM',
          scheduledEndTime: '10:20 AM',
        ),
      );
      service.addTestRequest(
        PatientConsultationRequest(
          id: 'doc-appt-2',
          patientId: 'p2',
          patientName: 'Karthik Rao',
          patientPhone: '9876500002',
          problemCategory: 'Cardiology',
          problemDescription: 'Annual Physical',
          severity: 'Moderate',
          submittedAt: today,
          status: 'PENDING',
          assignedDoctorId: doc.id,
          assignedDoctorName: doc.name,
          consultationMode: 'In-Person',
          durationMinutes: 30,
          bufferMinutes: 10,
          confirmedDate: ymd(today),
          confirmedTimeSlot: '11:00 AM',
          scheduledEndTime: '11:30 AM',
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: DentistTimelineScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ananya Verma'), findsOneWidget);
      expect(find.byKey(const Key('doctor_appt_mode_badge_doc-appt-1')), findsOneWidget);
      expect(find.text('Online'), findsWidgets);
      final startBtn = find.byKey(const Key('doctor_start_consultation_btn_doc-appt-1'));
      expect(startBtn, findsOneWidget);
      expect(find.byKey(const Key('doctor_mark_delayed_btn_doc-appt-1')), findsOneWidget);
      expect(find.byKey(const Key('doctor_mark_noshow_btn_doc-appt-1')), findsOneWidget);

      await tester.ensureVisible(startBtn);
      await tester.pump();
      // Tap Start Consultation -> transitions card to Complete Consultation & Busy – Online Consultation
      await tester.tap(startBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('doctor_complete_consultation_btn_doc-appt-1')), findsOneWidget);
      expect(find.textContaining('Busy – Online Consultation'), findsWidgets);
    });

    testWidgets('DoctorSlotManagementDialog renders manual slot block UI', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final doc = makeDoctor();
      PatientProblemService().addTestDoctor(doc);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DoctorSlotManagementDialog(
                initialDoctor: doc,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Working Days & Slots'), findsOneWidget);
      expect(find.textContaining('Configured Working Days'), findsOneWidget);
    });

    testWidgets('AdminDashboardScreen displays Hybrid Scheduling Monitor and Rules button without overflow', (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      ApiService.debugAdminAppointmentsOverride = () async => [
            {
              'id': 'adm-1',
              'date': '2026-11-26',
              'time_slot': '10:00 AM',
              'scheduledEndTime': '10:30 AM',
              'consultationMode': 'In-Person',
              'status': 'DELAYED',
              'delayMinutes': 15,
              'estimatedStartTime': '10:15 AM',
              'patient': {'id': 'p1', 'name': 'Riya Patient', 'phone': '9001122334'},
              'selectedDoctor': {'id': 'd1', 'name': 'Dr. Hybrid Specialist', 'specialty': 'Cardiology'},
            },
            {
              'id': 'adm-2',
              'date': '2026-11-26',
              'time_slot': '10:40 AM',
              'scheduledEndTime': '11:00 AM',
              'consultationMode': 'Online',
              'status': 'CONFIRMED',
              'delayMinutes': 15,
              'estimatedStartTime': '10:55 AM',
              'rescheduleRequestStatus': 'PENDING',
              'rescheduleRequestedDate': '2026-11-27',
              'rescheduleRequestedSlot': '11:00 AM',
              'rescheduleRequestReason': 'Doctor delayed 15m',
              'patient': {'id': 'p2', 'name': 'Karan Next', 'phone': '9001122335'},
              'selectedDoctor': {'id': 'd1', 'name': 'Dr. Hybrid Specialist', 'specialty': 'Cardiology'},
            }
          ];

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AdminDashboardScreen(initialTab: 4)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.ensureVisible(find.byKey(const Key('admin_hybrid_scheduling_monitor')));
      expect(find.byKey(const Key('admin_hybrid_scheduling_monitor')), findsOneWidget);
      expect(find.textContaining('Live Hybrid Doctor Calendar & Delay Monitor'), findsOneWidget);
      expect(find.textContaining('Delayed +15m'), findsOneWidget);
      expect(find.textContaining('Pending Reschedule Requests'), findsOneWidget);
      expect(find.byKey(const Key('admin_configure_hybrid_rules_btn')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('admin_configure_hybrid_rules_btn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('admin_configure_hybrid_rules_btn')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Configure Hybrid Scheduling Rules'), findsOneWidget);
      expect(find.byKey(const Key('rule_inperson_duration_input')), findsOneWidget);
      expect(find.byKey(const Key('rule_online_duration_input')), findsOneWidget);
      expect(find.byKey(const Key('rule_inperson_buffer_input')), findsOneWidget);
      expect(find.byKey(const Key('rule_online_buffer_input')), findsOneWidget);
      expect(find.byKey(const Key('save_hybrid_rules_btn')), findsOneWidget);
    });
  });
}
