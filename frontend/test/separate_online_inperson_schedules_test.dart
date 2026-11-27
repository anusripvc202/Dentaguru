import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/models/doctor_availability.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/widgets/doctor_slot_management_dialog.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookingRulesConfig.resetDefaults();
    BookingRulesConfig.debugNowOverride = DateTime(2026, 12, 7, 8, 0); // Monday 08:00 AM IST
  });

  tearDown(() {
    BookingRulesConfig.resetDefaults();
  });

  group('Separate Online and In-Person Working Hours & Dynamic Appointment Slots', () {
    test('1. DoctorScheduleModel & BookingRulesConfig generate exact independent Online (10 AM-12 PM, 20m+5m) and In-Person (12 PM-4 PM, 30m+10m) slots', () {
      final schedule = DoctorScheduleModel.fromJson({
        'workingDays': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        'startTime': '12:00 PM',
        'endTime': '04:00 PM',
        'hasBreak': false,
        'breaks': const [],
        'inPersonEnabled': true,
        'inPersonDurationMinutes': 30,
        'inPersonBufferMinutes': 10,
        'onlineEnabled': true,
        'useSeparateOnlineHours': true,
        'onlineWorkingDays': ['Monday', 'Wednesday', 'Friday'],
        'onlineStartTime': '10:00 AM',
        'onlineEndTime': '12:00 PM',
        'onlineHasBreak': false,
        'onlineBreaks': const [],
        'onlineDurationMinutes': 20,
        'onlineBufferMinutes': 5,
        'isConfigured': true,
      });

      expect(schedule.useSeparateOnlineHours, isTrue);

      final onlineSlots = BookingRulesConfig.generateSlotsWithBreaks(
        startTime: schedule.onlineStartTime!,
        endTime: schedule.onlineEndTime!,
        durationMinutes: schedule.onlineDurationMinutes,
        bufferMinutes: schedule.onlineBufferMinutes,
        stepMinutes: schedule.onlineDurationMinutes + schedule.onlineBufferMinutes,
        breaks: schedule.onlineBreaks,
      );
      expect(
        onlineSlots,
        equals(['10:00 AM', '10:25 AM', '10:50 AM', '11:15 AM', '11:40 AM']),
      );

      final inPersonSlots = BookingRulesConfig.generateSlotsWithBreaks(
        startTime: schedule.startTime,
        endTime: schedule.endTime,
        durationMinutes: schedule.inPersonDurationMinutes,
        bufferMinutes: schedule.inPersonBufferMinutes,
        stepMinutes: schedule.inPersonDurationMinutes + schedule.inPersonBufferMinutes,
        breaks: schedule.breaks,
      );
      expect(
        inPersonSlots,
        equals(['12:00 PM', '12:40 PM', '01:20 PM', '02:00 PM', '02:40 PM', '03:20 PM']),
      );
    });

    testWidgets(
      '2. DoctorSlotManagementDialog displays separate Online Consultation Schedule (working days, start/end time, breaks, preview) when Use separate Online working hours is enabled',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final doc = DoctorModel(
          id: 'doc-neuro-1',
          name: 'Dr. Neuro Specialist',
          specialty: 'Neurology',
          qualification: 'MD, DM',
          experienceYears: 10,
          rating: 4.9,
          reviewCount: 25,
          clinicName: 'GS Brain Clinic',
          phone: '9876500001',
          email: 'neuro@gshealth.in',
          status: 'Available',
          nextAvailableSlots: const [],
          consultationFee: '800',
          onlineConsultationEnabled: true,
          inPersonConsultationEnabled: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: DoctorSlotManagementDialog(
                  initialDoctor: doc,
                  isDoctorSelfManage: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        // Initially separate online schedule section is hidden
        expect(find.byKey(const Key('separate_online_schedule_section')), findsNothing);

        // Toggle "Use separate Online working hours" ON
        final sepSwitch = find.byKey(const Key('separate_online_hours_switch'));
        await tester.ensureVisible(sepSwitch);
        await tester.tap(sepSwitch);
        await tester.pump(const Duration(milliseconds: 300));

        // Separate Online Consultation Schedule section appears with independent working days, start/end time, and break controls
        expect(find.byKey(const Key('separate_online_schedule_section')), findsOneWidget);
        expect(find.text('Online Consultation Schedule'), findsOneWidget);
        expect(find.byKey(const Key('online_start_time_dropdown')), findsOneWidget);
        expect(find.byKey(const Key('online_end_time_dropdown')), findsOneWidget);
        expect(find.byKey(const Key('online_schedule_break_switch')), findsOneWidget);
        expect(find.byKey(const Key('online_working_day_chip_Mon')), findsOneWidget);
        expect(find.byKey(const Key('online_generated_slots_preview')), findsOneWidget);

        // Enable Online break and verify Online Break Start / End dropdowns appear
        await tester.ensureVisible(find.byKey(const Key('online_schedule_break_switch')));
        await tester.tap(find.byKey(const Key('online_schedule_break_switch')));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byKey(const Key('online_break_start_dropdown')), findsOneWidget);
        expect(find.byKey(const Key('online_break_end_dropdown')), findsOneWidget);
      },
    );

    testWidgets(
      '3. Patient Booking Screen (BookVisitFlowDialog) displays ONLY Online slots when Online Consultation is selected and ONLY In-Person slots when In-Person Consultation is selected',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1100);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final service = PatientProblemService();
        final targetDate = DateTime(2026, 12, 7); // Monday
        final doc = DoctorModel(
          id: 'doc-hybrid-sep',
          name: 'Dr. Separate Schedule',
          specialty: 'Cardiology',
          qualification: 'MD',
          experienceYears: 8,
          rating: 4.8,
          reviewCount: 15,
          clinicName: 'Lotus Heart Center',
          phone: '9876500002',
          email: 'hybridsep@gshealth.in',
          status: 'Available',
          nextAvailableSlots: const [],
          consultationFee: '700',
          onlineConsultationEnabled: true,
          inPersonConsultationEnabled: true,
        );

        // Seed Online availability (10:00 AM - 12:00 PM: 10:00, 10:25, 10:50, 11:15, 11:40)
        service.seedAvailabilityForTest(
          doc.id,
          targetDate,
          const DoctorAvailabilityModel(
            dentistId: 'doc-hybrid-sep',
            date: '2026-12-07',
            dayOfWeek: 'Monday',
            startTime: '10:00 AM',
            endTime: '12:00 PM',
            slotDurationMinutes: 20,
            consultationType: 'Online',
            consultationDurationMinutes: 20,
            bufferMinutes: 5,
            hasBreak: false,
            allSlots: ['10:00 AM', '10:25 AM', '10:50 AM', '11:15 AM', '11:40 AM'],
            availableSlots: ['10:00 AM', '10:25 AM', '10:50 AM', '11:15 AM', '11:40 AM'],
          ),
          consultationType: 'Online',
        );

        // Seed In-Person availability (12:00 PM - 04:00 PM: 12:00, 12:40, 01:20, 02:00, 02:40, 03:20)
        service.seedAvailabilityForTest(
          doc.id,
          targetDate,
          const DoctorAvailabilityModel(
            dentistId: 'doc-hybrid-sep',
            date: '2026-12-07',
            dayOfWeek: 'Monday',
            startTime: '12:00 PM',
            endTime: '04:00 PM',
            slotDurationMinutes: 30,
            consultationType: 'In-Person',
            consultationDurationMinutes: 30,
            bufferMinutes: 10,
            hasBreak: false,
            allSlots: ['12:00 PM', '12:40 PM', '01:20 PM', '02:00 PM', '02:40 PM', '03:20 PM'],
            availableSlots: ['12:00 PM', '12:40 PM', '01:20 PM', '02:00 PM', '02:40 PM', '03:20 PM'],
          ),
          consultationType: 'In-Person',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: BookVisitFlowDialog(
                  preselectedDoctor: doc,
                  initialConsultationMode: 'Online',
                  initialDate: targetDate,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        // In Online mode: displays ONLY Online slots (10:00 AM .. 11:40 AM), NEVER In-Person slots (12:00 PM .. 03:20 PM)
        expect(find.text('10:00 AM'), findsOneWidget);
        expect(find.text('10:25 AM'), findsOneWidget);
        expect(find.text('10:50 AM'), findsOneWidget);
        expect(find.text('11:15 AM'), findsOneWidget);
        expect(find.text('11:40 AM'), findsOneWidget);
        expect(find.text('12:00 PM'), findsNothing);
        expect(find.text('12:40 PM'), findsNothing);
        expect(find.text('01:20 PM'), findsNothing);

        // Switch to In-Person mode
        await tester.tap(find.byKey(const Key('booking_mode_in_person')));
        await tester.pump(const Duration(milliseconds: 500));

        // In In-Person mode: displays ONLY In-Person slots (12:00 PM .. 03:20 PM), NEVER Online slots (10:00 AM .. 11:40 AM)
        expect(find.text('12:00 PM'), findsOneWidget);
        expect(find.text('12:40 PM'), findsOneWidget);
        expect(find.text('01:20 PM'), findsOneWidget);
        expect(find.text('02:00 PM'), findsOneWidget);
        expect(find.text('02:40 PM'), findsOneWidget);
        expect(find.text('03:20 PM'), findsOneWidget);
        expect(find.text('10:00 AM'), findsNothing);
        expect(find.text('10:25 AM'), findsNothing);
        expect(find.text('11:40 AM'), findsNothing);
      },
    );
  });
}
