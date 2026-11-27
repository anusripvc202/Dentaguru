import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/features/admin/presentation/screens/admin_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookingRulesConfig.resetDefaults();
    ApiService.debugAdminAppointmentsOverride = null;
  });

  tearDown(() {
    BookingRulesConfig.resetDefaults();
    ApiService.debugAdminAppointmentsOverride = null;
  });

  group('Live Hybrid Doctor Calendar — Current & Next Patient Calculation (Asia/Kolkata)', () {
    final consecutiveAppointments = <Map<String, dynamic>>[
      {
        'id': 'appt-a',
        'patientId': 'pat-a',
        'patientName': 'Patient A',
        'date': '2026-11-27',
        'timeSlot': '09:00 AM',
        'scheduledEndTime': '09:30 AM',
        'consultationMode': 'In-Person',
        'status': 'CONFIRMED',
      },
      {
        'id': 'appt-b',
        'patientId': 'pat-b',
        'patientName': 'Patient B',
        'date': '2026-11-27',
        'timeSlot': '09:30 AM',
        'scheduledEndTime': '10:00 AM',
        'consultationMode': 'In-Person',
        'status': 'CONFIRMED',
      },
      {
        'id': 'appt-c',
        'patientId': 'pat-c',
        'patientName': 'Patient C',
        'date': '2026-11-27',
        'timeSlot': '10:00 AM',
        'scheduledEndTime': '10:30 AM',
        'consultationMode': 'In-Person',
        'status': 'CONFIRMED',
      },
    ];

    test('1. Before appointment start (08:45 AM): No current patient, Next is Patient A', () {
      final result = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: consecutiveAppointments,
        nowOverride: DateTime(2026, 11, 27, 8, 45),
      );

      expect(result['currentAppointment'], isNull);
      expect(result['nextAppointment'], isNotNull);
      expect((result['nextAppointment'] as Map)['patientName'], equals('Patient A'));
      expect((result['nextAppointment'] as Map)['scheduledStartTime'], equals('09:00 AM'));
    });

    test('2. Multiple consecutive appointments across 09:15, 09:30, 09:45, 10:00, and 10:45 AM', () {
      // 09:15 AM -> Current: Patient A, Next: Patient B
      final at0915 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: consecutiveAppointments,
        nowOverride: DateTime(2026, 11, 27, 9, 15),
      );
      expect((at0915['currentAppointment'] as Map)['patientName'], equals('Patient A'));
      expect((at0915['currentAppointment'] as Map)['scheduledStartTime'], equals('09:00 AM'));
      expect((at0915['currentAppointment'] as Map)['scheduledEndTime'], equals('09:30 AM'));
      expect((at0915['nextAppointment'] as Map)['patientName'], equals('Patient B'));
      expect((at0915['nextAppointment'] as Map)['scheduledStartTime'], equals('09:30 AM'));

      // 09:30 AM (exact end of Patient A) -> Current: Patient B, Next: Patient C
      final at0930 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: consecutiveAppointments,
        nowOverride: DateTime(2026, 11, 27, 9, 30),
      );
      expect((at0930['currentAppointment'] as Map)['patientName'], equals('Patient B'));
      expect((at0930['nextAppointment'] as Map)['patientName'], equals('Patient C'));

      // 09:45 AM -> Current: Patient B, Next: Patient C
      final at0945 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: consecutiveAppointments,
        nowOverride: DateTime(2026, 11, 27, 9, 45),
      );
      expect((at0945['currentAppointment'] as Map)['patientName'], equals('Patient B'));
      expect((at0945['nextAppointment'] as Map)['patientName'], equals('Patient C'));

      // 10:00 AM (exact end of Patient B) -> Current: Patient C, Next: null (No next patient)
      final at1000 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: consecutiveAppointments,
        nowOverride: DateTime(2026, 11, 27, 10, 0),
      );
      expect((at1000['currentAppointment'] as Map)['patientName'], equals('Patient C'));
      expect(at1000['nextAppointment'], isNull);

      // 10:45 AM (after all appointments ended) -> Current: null, Next: null
      final at1045 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: consecutiveAppointments,
        nowOverride: DateTime(2026, 11, 27, 10, 45),
      );
      expect(at1045['currentAppointment'], isNull);
      expect(at1045['nextAppointment'], isNull);
      expect(at1045['currentAvailability'], equals('Available'));
    });

    test('3. Completed, Cancelled, No-Show, Pending, and Duplicate records are excluded', () {
      final mixedAppointments = <Map<String, dynamic>>[
        // Active interval (09:00 - 09:30) but already COMPLETED -> must NOT appear as Current
        {
          'id': 'appt-completed',
          'patientId': 'pat-1',
          'patientName': 'Completed Patient',
          'date': '2026-11-27',
          'timeSlot': '09:00 AM',
          'consultationMode': 'In-Person',
          'status': 'COMPLETED',
        },
        // Upcoming (09:30) but CANCELLED -> must NOT appear as Next
        {
          'id': 'appt-cancelled',
          'patientId': 'pat-2',
          'patientName': 'Cancelled Patient',
          'date': '2026-11-27',
          'timeSlot': '09:30 AM',
          'consultationMode': 'In-Person',
          'status': 'CANCELLED',
        },
        // Upcoming (10:00) but NO_SHOW -> must NOT appear as Next
        {
          'id': 'appt-noshow',
          'patientId': 'pat-3',
          'patientName': 'NoShow Patient',
          'date': '2026-11-27',
          'timeSlot': '10:00 AM',
          'consultationMode': 'In-Person',
          'status': 'NO_SHOW',
        },
        // Upcoming (10:30) but PENDING (unconfirmed) -> must NOT appear as Next
        {
          'id': 'appt-pending',
          'patientId': 'pat-4',
          'patientName': 'Pending Unconfirmed Patient',
          'date': '2026-11-27',
          'timeSlot': '10:30 AM',
          'consultationMode': 'In-Person',
          'status': 'PENDING',
        },
        // Upcoming (11:00) CONFIRMED -> MUST be selected as Next
        {
          'id': 'appt-confirmed',
          'patientId': 'pat-5',
          'patientName': 'Confirmed Next Patient',
          'date': '2026-11-27',
          'timeSlot': '11:00 AM',
          'consultationMode': 'Online',
          'status': 'CONFIRMED',
        },
      ];

      final res = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: mixedAppointments,
        nowOverride: DateTime(2026, 11, 27, 9, 10),
      );

      expect(res['currentAppointment'], isNull);
      expect(res['nextAppointment'], isNotNull);
      expect((res['nextAppointment'] as Map)['patientName'], equals('Confirmed Next Patient'));
      expect((res['nextAppointment'] as Map)['scheduledStartTime'], equals('11:00 AM'));
    });

    test('4. Online (20m) vs In-Person (30m) durations and duplicate patient prevention', () {
      final hybridAppointments = <Map<String, dynamic>>[
        // Online appointment at 09:00 AM without explicit scheduledEndTime -> defaults to 20m (09:00 AM - 09:20 AM)
        {
          'id': 'online-1',
          'patientId': 'pat-anu',
          'patientName': 'anu',
          'date': '2026-11-27',
          'timeSlot': '09:00 AM',
          'consultationMode': 'Online',
          'status': 'CONFIRMED',
        },
        // Duplicate record for same patient 'anu' at 09:00 AM -> must never appear as Next
        {
          'id': 'online-1-dup',
          'patientId': 'pat-anu',
          'patientName': 'anu',
          'date': '2026-11-27',
          'timeSlot': '09:00 AM',
          'consultationMode': 'Online',
          'status': 'CONFIRMED',
        },
      ];

      // At 09:15 AM (within 20m Online consultation window 09:00 - 09:20): Current is anu, Next is null
      final at0915 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: hybridAppointments,
        nowOverride: DateTime(2026, 11, 27, 9, 15),
      );
      expect((at0915['currentAppointment'] as Map)['patientName'], equals('anu'));
      expect((at0915['currentAppointment'] as Map)['consultationType'], equals('Online'));
      expect((at0915['currentAppointment'] as Map)['scheduledEndTime'], equals('09:20 AM'));
      expect(at0915['nextAppointment'], isNull);

      // At 09:20 AM (exact end of 20m Online consultation): Current is immediately removed!
      final at0920 = BookingRulesConfig.evaluateDoctorLiveSchedule(
        doctorId: 'doc-1',
        doctorName: 'Dr. sri',
        appointments: hybridAppointments,
        nowOverride: DateTime(2026, 11, 27, 9, 20),
      );
      expect(at0920['currentAppointment'], isNull);
      expect(at0920['nextAppointment'], isNull);
    });

    testWidgets(
      '5. AdminDashboardScreen dynamically updates Current and Next via 30s auto-refresh timer and app resume lifecycle, and hides expired appointments',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        BookingRulesConfig.debugNowOverride = DateTime(2026, 11, 27, 9, 15);

        ApiService.debugAdminAppointmentsOverride = () async => [
              {
                'id': 'a1',
                'date': '2026-11-27',
                'time_slot': '09:00 AM',
                'scheduledEndTime': '09:30 AM',
                'consultationMode': 'In-Person',
                'status': 'CONFIRMED',
                'patient': {'id': 'pa', 'name': 'Patient A', 'phone': '9000000001'},
                'selectedDoctor': {'id': 'doc-sri', 'name': 'Dr. sri', 'specialty': 'Dentistry'},
              },
              {
                'id': 'a2',
                'date': '2026-11-27',
                'time_slot': '09:30 AM',
                'scheduledEndTime': '10:00 AM',
                'consultationMode': 'Online',
                'status': 'CONFIRMED',
                'patient': {'id': 'pb', 'name': 'Patient B', 'phone': '9000000002'},
                'selectedDoctor': {'id': 'doc-sri', 'name': 'Dr. sri', 'specialty': 'Dentistry'},
              },
              {
                'id': 'a3',
                'date': '2026-11-27',
                'time_slot': '10:00 AM',
                'scheduledEndTime': '10:30 AM',
                'consultationMode': 'In-Person',
                'status': 'CONFIRMED',
                'patient': {'id': 'pc', 'name': 'Patient C', 'phone': '9000000003'},
                'selectedDoctor': {'id': 'doc-sri', 'name': 'Dr. sri', 'specialty': 'Dentistry'},
              },
            ];

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: AdminDashboardScreen(initialTab: 4)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        final monitorFinder = find.byKey(const Key('admin_hybrid_scheduling_monitor'));
        expect(monitorFinder, findsOneWidget);

        // At 09:15 AM: Current is Patient A (09:00 AM–09:30 AM), Next is Patient B (09:30 AM–10:00 AM)
        expect(
          find.descendant(
            of: monitorFinder,
            matching: find.textContaining('Current Consultation: Patient A • In-Person • 09:00 AM–09:30 AM • Ongoing'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: monitorFinder,
            matching: find.textContaining('Next Patient: Patient B • Online at 09:30 AM–10:00 AM'),
          ),
          findsOneWidget,
        );

        // Advance time to 09:30 AM and let the 30-second periodic auto-refresh timer fire automatically
        BookingRulesConfig.debugNowOverride = DateTime(2026, 11, 27, 9, 30);
        await tester.pump(const Duration(seconds: 30));

        // Now Patient A (09:00 AM) has ended and is removed from Current; Current is Patient B, Next is Patient C
        expect(
          find.descendant(
            of: monitorFinder,
            matching: find.textContaining('Patient A'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: monitorFinder,
            matching: find.textContaining('Current Consultation: Patient B • Online • 09:30 AM–10:00 AM • Ongoing'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: monitorFinder,
            matching: find.textContaining('Next Patient: Patient C • In-Person at 10:00 AM–10:30 AM'),
          ),
          findsOneWidget,
        );

        // Advance time to 10:45 AM (after all appointments have ended) and simulate returning to the app (resumed)
        BookingRulesConfig.debugNowOverride = DateTime(2026, 11, 27, 10, 45);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 300));

        // Both Current and Next show the required empty states, and expired times are completely hidden
        expect(
          find.descendant(of: monitorFinder, matching: find.text('No ongoing consultation.')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: monitorFinder, matching: find.text('No upcoming appointments.')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: monitorFinder, matching: find.textContaining('09:00 AM')),
          findsNothing,
        );
        expect(
          find.descendant(of: monitorFinder, matching: find.textContaining('09:30 AM')),
          findsNothing,
        );
        expect(
          find.descendant(of: monitorFinder, matching: find.textContaining('10:00 AM')),
          findsNothing,
        );
      },
    );
  });
}
