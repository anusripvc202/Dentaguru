import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/services/firebase_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/services/session_service.dart';
import 'package:dentaguru/features/patient/presentation/screens/patient_dashboard.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookingRulesConfig.resetDefaults();
    BookingRulesConfig.debugNowOverride = DateTime(2026, 12, 9, 9, 0);
    FirebaseService.debugNavigateOverride = null;
    FirebaseService.clearPendingNotificationForTesting();
    await SessionService().clearSession();
    await PatientProblemService().clearAllDataAndStorage();
  });

  tearDown(() async {
    BookingRulesConfig.resetDefaults();
    FirebaseService.debugNavigateOverride = null;
    FirebaseService.clearPendingNotificationForTesting();
    await SessionService().clearSession();
    await PatientProblemService().clearAllDataAndStorage();
  });

  group('Phase 1 Fix 5 — Complete FCM Notification Tap Navigation (Foreground, Background, Terminated)', () {
    test('Foreground local notification tap parses JSON payload and routes Early Slot Release to booking deep-link', () {
      final navigatedRoutes = <String>[];
      FirebaseService.debugNavigateOverride = navigatedRoutes.add;

      final payload = jsonEncode({
        'notificationType': 'EARLY_SLOT_RELEASED',
        'doctorId': 'doc-cardio-1',
        'doctorName': 'Dr. Anjali Rao',
        'appointmentDate': '2026-12-10',
        'startTime': '09:20 AM',
        'consultationType': 'Online',
      });

      FirebaseService.handleLocalNotificationPayloadString(payload);

      expect(navigatedRoutes.length, 1);
      final uri = Uri.parse(navigatedRoutes.first);
      expect(uri.path, '/patient');
      expect(uri.queryParameters['openBookingDoctorId'], 'doc-cardio-1');
      expect(uri.queryParameters['bookingDate'], '2026-12-10');
      expect(uri.queryParameters['bookingSlot'], '09:20 AM');
      expect(uri.queryParameters['bookingMode'], 'Online');
    });

    test('Background notification tap routes Patient appointment/prescription alerts and Doctor request/referral alerts accurately', () {
      final navigatedRoutes = <String>[];
      FirebaseService.debugNavigateOverride = navigatedRoutes.add;

      FirebaseService.handleNotificationPayload(
        {'type': 'appointment_confirmed', 'appointmentId': 'apt-1'},
        source: 'background_tap',
        userRoleOverride: 'Patient',
      );
      FirebaseService.handleNotificationPayload(
        {'type': 'consultation_completed', 'recordId': 'rec-1'},
        source: 'background_tap',
        userRoleOverride: 'Patient',
      );
      FirebaseService.handleNotificationPayload(
        {'type': 'appointment_request', 'appointmentId': 'apt-2'},
        source: 'background_tap',
        userRoleOverride: 'Dentist',
      );
      FirebaseService.handleNotificationPayload(
        {'type': 'referral', 'referralId': 'ref-1'},
        source: 'background_tap',
        userRoleOverride: 'Dentist',
      );

      expect(navigatedRoutes, [
        '/patient?tab=2',
        '/patient?tab=3',
        '/dentist?tab=0',
        '/dentist?tab=2',
      ]);
    });

    test('Terminated-app notification tap defers while session is absent and replays once session is active', () async {
      // No active session & no debugNavigateOverride -> defers safely instead of dropping
      FirebaseService.handleNotificationPayload(
        {'type': 'appointment_confirmed', 'appointmentId': 'apt-cold-1'},
        source: 'terminated_launch',
      );
      expect(FirebaseService.pendingNotificationDataForTesting, isNotNull);
      expect(FirebaseService.pendingNotificationDataForTesting!['appointmentId'], 'apt-cold-1');

      // Session restored + navigation handler ready -> consumePendingNotificationNavigation replays it
      await SessionService().saveSession(
        token: 'patient-jwt-1',
        role: 'Patient',
        userId: 'pat-1',
        name: 'Anu',
        email: 'anu@test.com',
        phone: '9876543210',
      );
      final navigatedRoutes = <String>[];
      FirebaseService.debugNavigateOverride = navigatedRoutes.add;

      final consumed = FirebaseService.consumePendingNotificationNavigation();
      expect(consumed, isTrue);
      expect(FirebaseService.pendingNotificationDataForTesting, isNull);
      expect(navigatedRoutes, ['/patient?tab=2']);
    });
  });

  group('Phase 1 Fix 4 & 5 UI — Booking Screen Live Refresh Fallback & Deep-Link Preselection', () {
    testWidgets(
      'BookVisitFlowDialog refreshes availability periodically, clears a newly occupied slot with unavailability notice, and disposes timers cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-live-1',
          name: 'Anu Patient',
          phone: '9876543210',
          city: 'Hyderabad',
        );
        final doc = DoctorModel(
          id: 'doc-live-1',
          userId: 'user-doc-live-1',
          name: 'Dr. Anjali Rao',
          specialty: 'Cardiology',
          qualification: 'MD',
          experienceYears: 10,
          rating: 4.9,
          reviewCount: 20,
          clinicName: 'GS Health Heart Care',
          phone: '9000000002',
          email: 'anjali@gshealth.test',
          status: 'Available',
          nextAvailableSlots: const ['09:00 AM', '09:30 AM', '10:00 AM'],
          consultationFee: '600',
        );
        service.addTestDoctor(doc);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: BookVisitFlowDialog(
                  preselectedDoctor: doc,
                  initialDate: DateTime(2026, 12, 10),
                  initialTimeSlot: '09:30 AM',
                  autoRefreshInterval: const Duration(milliseconds: 250),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Manual refresh button exists and deep-linked slot is present
        expect(find.byKey(const Key('booking_refresh_slots_btn')), findsOneWidget);
        expect(find.text('09:30 AM'), findsOneWidget);

        // Simulate another patient booking 09:30 AM concurrently while dialog is open
        service.addTestRequest(
          PatientConsultationRequest(
            id: 'concurrent-appt-1',
            patientId: 'other-patient',
            patientName: 'Other Patient',
            patientPhone: '9999999999',
            problemCategory: 'In-Person - Checkup',
            problemDescription: 'Booked concurrently',
            severity: 'Mild',
            submittedAt: DateTime(2026, 12, 9),
            status: 'CONFIRMED',
            assignedDoctorId: doc.id,
            assignedDoctorName: doc.name,
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '09:30 AM',
            consultationMode: 'In-Person',
          ),
        );

        // Let periodic refresh fallback trigger
        await tester.pump(const Duration(milliseconds: 350));

        // Selected slot should now be cleared with clear unavailability message
        expect(find.byKey(const Key('booking_slot_unavailable_notice')), findsOneWidget);
        expect(find.text('This slot is no longer available. Please select another time.'), findsOneWidget);

        // Unmount dialog to verify timer & Realtime channel dispose cleanly without pending timers
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'PatientDashboardScreen respects notification deep-link initialTabIndex and opens preselected booking dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-dl-1',
          name: 'Anu Patient',
          phone: '9876543210',
          city: 'Hyderabad',
        );
        final doc = DoctorModel(
          id: 'doc-dl-1',
          userId: 'user-doc-dl-1',
          name: 'Dr. Kavya Online',
          specialty: 'Cardiology',
          qualification: 'MD',
          experienceYears: 8,
          rating: 4.8,
          reviewCount: 15,
          clinicName: 'GS Health',
          phone: '9000000003',
          email: 'kavya@gshealth.test',
          status: 'Available',
          nextAvailableSlots: const ['09:00 AM', '09:20 AM'],
          consultationFee: '500',
        );
        service.addTestDoctor(doc);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: PatientDashboardScreen(
                initialTabIndex: 0,
                openBookingDoctorId: 'doc-dl-1',
                initialBookingDate: '2026-12-10',
                initialBookingSlot: '09:20 AM',
                initialBookingMode: 'Online',
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Deep-linked BookVisitFlowDialog opened directly on Step 2 for Dr. Kavya Online
        expect(find.byType(BookVisitFlowDialog), findsOneWidget);
        expect(find.text('Dr. Kavya Online'), findsWidgets);
        expect(find.byKey(const Key('booking_mode_online')), findsOneWidget);

        // Unmount cleanly so periodic timer is disposed
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
