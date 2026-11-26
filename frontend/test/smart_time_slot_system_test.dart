import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/models/doctor_availability.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/widgets/doctor_slot_management_dialog.dart';
import 'package:dentaguru/features/dentist/presentation/widgets/doctor_visits_calendar.dart';
import 'package:dentaguru/features/patient/presentation/widgets/book_visit_flow_dialog.dart';

void main() {
  group('GS Health — Smart Time Slot System Flutter Verification', () {
    test('1. DoctorScheduleModel & DoctorAvailabilityModel serialize multiple breaks, 15/20/30/45/60 durations, Online/In-Person settings, buffers, daily cap & released slots', () {
      final schedule = DoctorScheduleModel.fromJson({
        'workingDays': ['Monday', 'Wednesday', 'Friday'],
        'startTime': '09:00 AM',
        'endTime': '05:00 PM',
        'breaks': [
          {'startTime': '11:30 AM', 'endTime': '12:00 PM', 'label': 'Coffee'},
          {'startTime': '01:00 PM', 'endTime': '02:00 PM', 'label': 'Lunch'},
        ],
        'inPersonEnabled': true,
        'inPersonDurationMinutes': 30,
        'inPersonBufferMinutes': 10,
        'onlineEnabled': true,
        'onlineDurationMinutes': 20,
        'onlineBufferMinutes': 5,
        'onlineStartTime': '10:00 AM',
        'onlineEndTime': '04:00 PM',
        'maxAppointmentsPerDay': 12,
        'allowSimultaneousOnlineAndInPerson': false,
        'isConfigured': true,
      });

      expect(schedule.breaks.length, 2);
      expect(schedule.inPersonDurationMinutes, 30);
      expect(schedule.onlineDurationMinutes, 20);
      expect(schedule.inPersonBufferMinutes, 10);
      expect(schedule.onlineBufferMinutes, 5);
      expect(schedule.onlineStartTime, '10:00 AM');
      expect(schedule.onlineEndTime, '04:00 PM');
      expect(schedule.maxAppointmentsPerDay, 12);
      expect(schedule.allowSimultaneousOnlineAndInPerson, false);

      final roundTrip = DoctorScheduleModel.fromJson(schedule.toJson());
      expect(roundTrip.breaks.length, 2);
      expect(roundTrip.onlineDurationMinutes, 20);
      expect(roundTrip.maxAppointmentsPerDay, 12);

      final avail = DoctorAvailabilityModel.fromJson({
        'dentistId': 'doc-smart-1',
        'date': '2026-12-10',
        'consultationType': 'Online',
        'consultationDurationMinutes': 20,
        'bufferMinutes': 5,
        'allSlots': ['09:00 AM', '09:20 AM', '09:40 AM'],
        'availableSlots': ['09:00 AM', '09:40 AM'],
        'lockedSlots': ['09:20 AM'],
        'releasedSlots': [
          {
            'releasedSlotId': 'rel-slot-1',
            'startTime': '09:40 AM',
            'endTime': '10:00 AM',
            'consultationType': 'Online',
            'isReleasedSlot': true,
          },
        ],
        'maxAppointmentsPerDay': 12,
        'dailyLimitReached': false,
      });
      expect(avail.lockedSlots, ['09:20 AM']);
      expect(avail.releasedSlots.length, 1);
      expect(avail.releasedSlots.first['releasedSlotId'], 'rel-slot-1');
    });

    testWidgets('2. DoctorSlotManagementDialog exposes 15/20/30/45/60 durations, multiple breaks, Online/In-Person rules, daily cap, and custom blocked time ranges with zero overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testDoc = DoctorModel(
        id: 'doc-smart-ui-1',
        name: 'Dr. Smart Schedule',
        specialty: 'General Medicine',
        qualification: 'MBBS, MD',
        experienceYears: 8,
        rating: 4.9,
        reviewCount: 40,
        clinicName: 'GS Health Clinic',
        phone: '9876543210',
        email: 'smart@gshealth.test',
        status: 'Available',
        nextAvailableSlots: const ['09:00 AM', '09:30 AM'],
        consultationFee: '500',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DoctorSlotManagementDialog(
                initialDoctor: testDoc,
                isDoctorSelfManage: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('schedule_duration_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('add_extra_break_btn')), findsOneWidget);
      expect(find.byKey(const Key('smart_online_inperson_config_card')), findsOneWidget);
      expect(find.byKey(const Key('online_duration_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('in_person_buffer_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('online_buffer_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('max_appointments_per_day_input')), findsOneWidget);
      expect(find.byKey(const Key('allow_simultaneous_modes_switch')), findsOneWidget);
      expect(find.byKey(const Key('custom_blocked_range_card')), findsOneWidget);

      // Add a second break dynamically
      await tester.ensureVisible(find.byKey(const Key('add_extra_break_btn')));
      await tester.tap(find.byKey(const Key('add_extra_break_btn')));
      await tester.pump();
      expect(find.byKey(const Key('extra_break_start_0')), findsOneWidget);
      expect(find.byKey(const Key('extra_break_end_0')), findsOneWidget);
    });

    testWidgets('3. DoctorVisitsCalendarSection supports Monthly & Weekly views and displays Schedule Overview strip', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DoctorVisitsCalendarSection(
                  doctorId: 'doc-cal-1',
                  doctorName: 'Dr. Kavitha Rao',
                  assignedAppointments: const [],
                  receivedReferrals: const [],
                  initialSelectedDate: DateTime(2026, 12, 10),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('doctor_calendar_mode_monthly')), findsOneWidget);
      expect(find.byKey(const Key('doctor_calendar_mode_weekly')), findsOneWidget);
      expect(find.byKey(const Key('doctor_calendar_schedule_overview')), findsOneWidget);

      await tester.tap(find.byKey(const Key('doctor_calendar_mode_weekly')));
      await tester.pump();
      expect(find.byKey(const Key('doctor_calendar_weekly_view')), findsOneWidget);
    });

    testWidgets('4. BookVisitFlowDialog displays early released slots, earlier-slot notification preference toggle, and dynamic doctor duration hint with zero overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      BookingRulesConfig.debugNowOverride = DateTime(2026, 12, 9, 8, 0);
      addTearDown(() => BookingRulesConfig.debugNowOverride = null);

      final service = PatientProblemService();
      final doc = DoctorModel(
        id: 'doc-patient-smart-1',
        name: 'Dr. Smart Online',
        specialty: 'Cardiology',
        qualification: 'MBBS, MD',
        experienceYears: 10,
        rating: 4.8,
        reviewCount: 55,
        clinicName: 'GS Health Heart Center',
        phone: '9876500001',
        email: 'heart@gshealth.test',
        status: 'Available',
        nextAvailableSlots: const ['09:00 AM', '09:20 AM'],
        consultationFee: '700',
      );
      final targetDate = DateTime(2026, 12, 10);
      service.seedAvailabilityForTest(
        doc.id,
        targetDate,
        const DoctorAvailabilityModel(
          dentistId: 'doc-patient-smart-1',
          date: '2026-12-10',
          consultationType: 'Online',
          consultationDurationMinutes: 20,
          bufferMinutes: 5,
          allSlots: ['09:00 AM', '09:20 AM', '09:40 AM'],
          availableSlots: ['09:00 AM', '09:40 AM'],
          lockedSlots: ['09:20 AM'],
          releasedSlots: [
            {
              'releasedSlotId': 'rel-early-1',
              'startTime': '09:40 AM',
              'endTime': '10:00 AM',
              'consultationType': 'Online',
              'isReleasedSlot': true,
            },
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: BookVisitFlowDialog(
                preselectedDoctor: doc,
                initialConsultationMode: 'Online',
                initialDate: targetDate,
                enableAutoRefresh: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('booking_earlier_slot_pref_card')), findsOneWidget);
      expect(find.byKey(const Key('booking_notify_earlier_slots_switch')), findsOneWidget);
      expect(find.textContaining('Online duration: 20 mins (+5m buffer)'), findsOneWidget);
      expect(find.byKey(const Key('released_slot_chip_09:40_AM')), findsOneWidget);
      expect(find.textContaining('09:40 AM • Early'), findsOneWidget);
    });
  });
}
