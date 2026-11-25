import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    BookingRulesConfig.resetDefaults();
    await PatientProblemService().clearAllData();
  });

  tearDown(() async {
    BookingRulesConfig.resetDefaults();
    ApiService.debugFetchDentistsOverride = null;
    await PatientProblemService().clearAllData();
  });

  group('Phase 4: Configurable 30-Min Advance Booking, Online vs In-Person Mode & Real Fee', () {
    test('1. BookingRulesConfig enforces separately configurable 30-min advance rule and 6 distinct statuses', () {
      final today = DateTime(2026, 11, 24);
      final now1115 = DateTime(2026, 11, 24, 11, 15);
      final slots = ['10:30 AM', '11:00 AM', '11:30 AM', '11:45 AM', '12:00 PM'];

      // With default minAdvanceBookingMinutes = 30 at 11:15 AM:
      // 10:30, 11:00 (past) & 11:30 (+15m) excluded; 11:45 (+30m) & 12:00 (+45m) bookable!
      final filtered30 = BookingRulesConfig.filterBookableSlotsForDate(
        today,
        slots,
        nowOverride: now1115,
      );
      expect(filtered30, equals(['11:45 AM', '12:00 PM']));

      // Changing minAdvanceBookingMinutes independently to 45 without touching slot interval:
      BookingRulesConfig.minAdvanceBookingMinutes = 45;
      expect(BookingRulesConfig.defaultSlotIntervalMinutes, equals(30));
      final filtered45 = BookingRulesConfig.filterBookableSlotsForDate(
        today,
        slots,
        nowOverride: now1115,
      );
      expect(filtered45, equals(['12:00 PM']));

      // Future dates allow all published slots regardless of today's clock
      final tomorrow = DateTime(2026, 11, 25);
      expect(
        BookingRulesConfig.filterBookableSlotsForDate(tomorrow, slots, nowOverride: now1115),
        equals(slots),
      );

      // Past dates allow zero slots
      final yesterday = DateTime(2026, 11, 23);
      expect(
        BookingRulesConfig.filterBookableSlotsForDate(yesterday, slots, nowOverride: now1115),
        isEmpty,
      );

      // 6 distinct appointment status labels
      expect(BookingRulesConfig.formatAppointmentStatusLabel('PENDING'), equals('Pending'));
      expect(BookingRulesConfig.formatAppointmentStatusLabel('CONFIRMED'), equals('Confirmed'));
      expect(BookingRulesConfig.formatAppointmentStatusLabel('CANCELLED'), equals('Cancelled'));
      expect(BookingRulesConfig.formatAppointmentStatusLabel('COMPLETED'), equals('Completed'));
      expect(BookingRulesConfig.formatAppointmentStatusLabel('REJECTED'), equals('Rejected'));
      expect(BookingRulesConfig.formatAppointmentStatusLabel('RESCHEDULED'), equals('Rescheduled'));
    });

    testWidgets(
      '2. BookVisitFlowDialog supports Online vs In-Person selection, hides <30m slots on Today, and shows real doctor fee (never hardcoded ₹500)',
      (tester) async {
        tester.view.physicalSize = const Size(500, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        BookingRulesConfig.debugNowOverride = DateTime(2026, 11, 24, 11, 15);

        final doc = DoctorModel(
          id: 'doc-neuro-book-1',
          userId: 'usr-neuro-book-1',
          name: 'Dr. Aravind Menon',
          specialty: 'Neurology',
          qualification: 'MBBS, MD, DM',
          experienceYears: 12,
          rating: 4.9,
          reviewCount: 18,
          clinicName: 'Neuro Care Center',
          phone: '9000012345',
          email: 'aravind@neuro.in',
          status: 'Online',
          onlineStatus: 'Online',
          nextAvailableSlots: const ['10:30 AM', '11:30 AM', '12:00 PM'],
          consultationFee: '₹950',
        );

        final service = PatientProblemService();
        service.currentPatient = PatientProfile(
          id: 'pat-book-1',
          name: 'Sneha Nair',
          phone: '9888811111',
        );
        service.addTestDoctor(doc);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: BookVisitFlowDialog(
                  preselectedDoctor: doc,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select Online Consultation mode
        expect(find.byKey(const Key('booking_mode_in_person')), findsOneWidget);
        expect(find.byKey(const Key('booking_mode_online')), findsOneWidget);
        await tester.tap(find.byKey(const Key('booking_mode_online')));
        await tester.pumpAndSettle();

        // Tap Today chip (first chip in date selector: day '24')
        await tester.tap(find.text('24').first);
        await tester.pumpAndSettle();

        // On Today at 11:15 AM: 10:30 AM (past) and 11:30 AM (+15m < 30m) must NOT appear; 12:00 PM (+45m) MUST appear
        expect(find.text('10:30 AM'), findsNothing);
        expect(find.text('11:30 AM'), findsNothing);
        expect(find.text('12:00 PM'), findsOneWidget);

        await tester.tap(find.text('12:00 PM'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next: Reason for Visit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next: Review Booking Details'));
        await tester.pumpAndSettle();

        // Step 4 Review shows Online Consultation + real fee ₹950 (not ₹₹950 and not ₹500)
        expect(find.text('Online Consultation'), findsOneWidget);
        expect(find.text('₹950'), findsOneWidget);
        expect(find.text('₹₹950'), findsNothing);
        expect(find.text('₹500'), findsNothing);
      },
    );
  });
}
