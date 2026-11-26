import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:dentaguru/features/dentist/presentation/widgets/doctor_visits_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookingRulesConfig.resetDefaults();
    BookingRulesConfig.debugNowOverride = DateTime(2026, 12, 10, 9, 0);
    ApiService.debugDoctorVisitsCalendarOverride = null;
    await PatientProblemService().clearAllDataAndStorage();
  });

  tearDown(() async {
    BookingRulesConfig.resetDefaults();
    ApiService.debugDoctorVisitsCalendarOverride = null;
    await PatientProblemService().clearAllDataAndStorage();
  });

  testWidgets(
    'Scenario 1: Doctor with no appointments taps Appointments Calendar card on Today page -> sees 0 counts and empty date message',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = PatientProblemService();
      service.setDentistMode(true);
      service.registerDoctor(
        id: 'doc-empty',
        userId: 'user-doc-empty',
        name: 'Dr. Empty Calendar',
        specialty: 'General Medicine',
        qualification: 'MBBS',
        experienceYears: 4,
        clinicName: 'GS Health Clinic',
        phone: '9000000001',
        email: 'empty@gshealth.test',
        licenseNumber: 'MED-EMPTY',
        skipApiRegister: true,
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: DentistTimelineScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Appointments Calendar entry card on Today page
      final openCalCard = find.byKey(const Key('dentist_open_calendar_card'));
      expect(openCalCard, findsOneWidget);
      await tester.ensureVisible(openCalCard);
      await tester.tap(openCalCard);
      await tester.pumpAndSettle();

      // Dedicated calendar screen opened
      expect(find.byKey(const Key('doctor_appointments_calendar_screen')), findsOneWidget);
      expect(find.text('No appointments scheduled for this date.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('doctor_cal_stat_total_appointments')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Scenarios 2-8: Multiple dates & months, all statuses, Online vs In-Person, regular vs referred patients (deduplicated), filters, and strict doctor isolation',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appointments = <PatientConsultationRequest>[
        // 2026-12-10: 5 appointments for doc-A
        PatientConsultationRequest(
          id: 'apt-completed',
          patientId: 'PAT-101',
          patientName: 'Riya Sharma',
          patientPhone: '9876543210',
          problemCategory: 'Online - Cardiology Follow-up',
          problemDescription: 'Chest tightness while walking',
          symptoms: 'Shortness of breath',
          severity: 'Moderate',
          submittedAt: DateTime(2026, 12, 9),
          status: 'Completed',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2026-12-10',
          confirmedTimeSlot: '09:00 AM',
          consultationMode: 'Online',
        ),
        PatientConsultationRequest(
          id: 'apt-accepted',
          patientId: 'PAT-102',
          patientName: 'Arjun Nair',
          patientPhone: '9876543211',
          problemCategory: 'In-Person - ECG Evaluation',
          problemDescription: 'Routine cardiac evaluation',
          symptoms: 'None',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 9),
          status: 'Accepted',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2026-12-10',
          confirmedTimeSlot: '10:30 AM',
          consultationMode: 'In-Person',
        ),
        PatientConsultationRequest(
          id: 'apt-pending',
          patientId: 'PAT-103',
          patientName: 'Meera Iyer',
          patientPhone: '9876543212',
          problemCategory: 'Online - BP Review',
          problemDescription: 'Elevated evening blood pressure',
          symptoms: 'Headache',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 9),
          status: 'Pending',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2026-12-10',
          confirmedTimeSlot: '12:00 PM',
          consultationMode: 'Online',
        ),
        PatientConsultationRequest(
          id: 'apt-rejected',
          patientId: 'PAT-104',
          patientName: 'Karan Verma',
          patientPhone: '9876543213',
          problemCategory: 'In-Person - Consultation',
          problemDescription: 'Slot conflict inquiry',
          symptoms: 'Fatigue',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 9),
          status: 'Rejected',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2026-12-10',
          confirmedTimeSlot: '02:00 PM',
          consultationMode: 'In-Person',
        ),
        PatientConsultationRequest(
          id: 'apt-rescheduled',
          patientId: 'PAT-105',
          patientName: 'Sneha Reddy',
          patientPhone: '9876543214',
          problemCategory: 'In-Person - Rescheduled Cardiac Check',
          problemDescription: 'Moved to afternoon slot',
          symptoms: 'Palpitations',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 8),
          status: 'Rescheduled',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2026-12-10',
          confirmedTimeSlot: '04:00 PM',
          consultationMode: 'In-Person',
        ),
        // Second date in same month (2026-12-15)
        PatientConsultationRequest(
          id: 'apt-dec15',
          patientId: 'PAT-102',
          patientName: 'Arjun Nair',
          patientPhone: '9876543211',
          problemCategory: 'Online - Follow-up',
          problemDescription: 'Lab review',
          symptoms: 'None',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 10),
          status: 'Confirmed',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2026-12-15',
          confirmedTimeSlot: '11:00 AM',
          consultationMode: 'Online',
        ),
        // Next month date (2027-01-05)
        PatientConsultationRequest(
          id: 'apt-jan05',
          patientId: 'PAT-101',
          patientName: 'Riya Sharma',
          patientPhone: '9876543210',
          problemCategory: 'In-Person - Annual Checkup',
          problemDescription: 'Annual review',
          symptoms: 'None',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 10),
          status: 'Pending',
          assignedDoctorId: 'doc-A',
          assignedDoctorName: 'Dr. Anjali Rao',
          assignedDoctorSpecialty: 'Cardiology',
          confirmedDate: '2027-01-05',
          confirmedTimeSlot: '10:00 AM',
          consultationMode: 'In-Person',
        ),
        // Another doctor's appointment on 2026-12-10 (MUST NOT LEAK)
        PatientConsultationRequest(
          id: 'apt-doc-B',
          patientId: 'PAT-999',
          patientName: 'Secret Other Doctor Patient',
          patientPhone: '9999999999',
          problemCategory: 'In-Person - Ortho',
          problemDescription: 'Knee pain',
          symptoms: 'Pain',
          severity: 'Low',
          submittedAt: DateTime(2026, 12, 9),
          status: 'Completed',
          assignedDoctorId: 'doc-B',
          assignedDoctorName: 'Dr. Vikram Mehta',
          assignedDoctorSpecialty: 'Orthopedics',
          confirmedDate: '2026-12-10',
          confirmedTimeSlot: '09:30 AM',
          consultationMode: 'In-Person',
        ),
      ];

      final referrals = <PatientReferral>[
        // Accepted referral for Riya Sharma + intentional duplicate entry (must only count once!)
        PatientReferral(
          id: 'ref-1',
          referrerPatientId: 'PAT-200',
          referrerPatientName: 'Priya Referrer',
          referrerPatientPhone: '9123456789',
          referredPatientId: 'PAT-101',
          referredPatientName: 'Riya Sharma',
          referredPatientMobile: '9876543210',
          requiredSpecialist: 'Cardiology',
          clinicalComplaint: 'Chest tightness',
          doctorId: 'doc-A',
          doctorName: 'Dr. Anjali Rao',
          status: 'Accepted',
          referralDate: DateTime(2026, 12, 10, 8, 30),
        ),
        PatientReferral(
          id: 'ref-1',
          referrerPatientId: 'PAT-200',
          referrerPatientName: 'Priya Referrer',
          referrerPatientPhone: '9123456789',
          referredPatientId: 'PAT-101',
          referredPatientName: 'Riya Sharma',
          referredPatientMobile: '9876543210',
          requiredSpecialist: 'Cardiology',
          clinicalComplaint: 'Chest tightness',
          doctorId: 'doc-A',
          doctorName: 'Dr. Anjali Rao',
          status: 'Accepted',
          referralDate: DateTime(2026, 12, 10, 8, 30),
        ),
        // Pending referral on 2026-12-10
        PatientReferral(
          id: 'ref-2',
          referrerPatientId: 'PAT-102',
          referrerPatientName: 'Arjun Nair',
          referredPatientId: 'PAT-301',
          referredPatientName: 'Unbooked Friend',
          referredPatientMobile: '9111222333',
          requiredSpecialist: 'Cardiology',
          clinicalComplaint: 'BP check',
          doctorId: 'doc-A',
          doctorName: 'Dr. Anjali Rao',
          status: 'Pending',
          referralDate: DateTime(2026, 12, 10, 10, 0),
        ),
        // Rejected referral on 2026-12-10
        PatientReferral(
          id: 'ref-3',
          referrerPatientId: 'PAT-103',
          referrerPatientName: 'Meera Iyer',
          referredPatientId: 'PAT-302',
          referredPatientName: 'Declined Patient',
          referredPatientMobile: '9111222444',
          requiredSpecialist: 'Cardiology',
          clinicalComplaint: 'General',
          doctorId: 'doc-A',
          doctorName: 'Dr. Anjali Rao',
          status: 'Rejected',
          referralDate: DateTime(2026, 12, 10, 11, 0),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DoctorVisitsCalendarSection(
                  doctorId: 'doc-A',
                  doctorName: 'Dr. Anjali Rao',
                  doctorSpecialty: 'Cardiology',
                  assignedAppointments: appointments,
                  receivedReferrals: referrals,
                  initialSelectedDate: DateTime(2026, 12, 10),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Verify monthly appointment counts shown directly on dates
      expect(
        find.descendant(
          of: find.byKey(const Key('doctor_calendar_day_count_2026-12-10')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('doctor_calendar_day_count_2026-12-15')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      // Verify Daily Summary counts for 2026-12-10
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_total_appointments')), matching: find.text('5')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_accepted')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_pending')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_completed')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_rejected')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_rescheduled')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_online')), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_in_person')), matching: find.text('3')), findsOneWidget);

      // Verify deduplicated referral tracking counters (3 received, not 4!)
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_stat_referrals_received')), matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_ref_stat_accepted')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_ref_stat_pending')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_ref_stat_rejected')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('doctor_cal_ref_stat_completed')), matching: find.text('1')), findsOneWidget);

      // Verify visit card details: Patient ID, Reason, Online/In-Person labels, Referral badge, and zero leakage of doc-B
      expect(find.text('Patient ID: PAT-101'), findsOneWidget);
      expect(find.text('Reason: Chest tightness while walking'), findsOneWidget);
      expect(find.text('Online Consultation'), findsNWidgets(2));
      expect(find.text('In-Person Consultation'), findsNWidgets(3));
      expect(find.textContaining('Referred by: Priya Referrer'), findsOneWidget);
      expect(find.text('Secret Other Doctor Patient'), findsNothing);

      // Verify Filters: Online -> only 2 cards
      final onlineChip = find.byKey(const Key('doctor_calendar_mode_filter_Online'));
      await tester.ensureVisible(onlineChip);
      await tester.tap(onlineChip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-completed')), findsOneWidget);
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-pending')), findsOneWidget);
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-accepted')), findsNothing);

      // Reset via All, then filter Referred -> only Riya's referred visit
      final allChip = find.byKey(const Key('doctor_calendar_filter_All'));
      await tester.ensureVisible(allChip);
      await tester.tap(allChip);
      await tester.pump(const Duration(milliseconds: 200));
      final referredChip = find.byKey(const Key('doctor_calendar_filter_Referred'));
      await tester.ensureVisible(referredChip);
      await tester.tap(referredChip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-completed')), findsOneWidget);
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-accepted')), findsNothing);

      // Reset via All, select 2026-12-15 -> shows 1 appointment (Arjun Nair)
      await tester.ensureVisible(allChip);
      await tester.tap(allChip);
      await tester.pump(const Duration(milliseconds: 200));
      final dec15Cell = find.byKey(const Key('doctor_calendar_day_2026-12-15'));
      await tester.ensureVisible(dec15Cell);
      await tester.tap(dec15Cell);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-dec15')), findsOneWidget);
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-completed')), findsNothing);

      // Navigate to Next Month (January 2027) and select 2027-01-05
      final nextMonthBtn = find.byKey(const Key('doctor_calendar_next_month_btn'));
      await tester.ensureVisible(nextMonthBtn);
      await tester.tap(nextMonthBtn);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('January 2027'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('doctor_calendar_day_count_2027-01-05')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      final jan05Cell = find.byKey(const Key('doctor_calendar_day_2027-01-05'));
      await tester.ensureVisible(jan05Cell);
      await tester.tap(jan05Cell);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('doctor_calendar_visit_card_apt-jan05')), findsOneWidget);
    },
  );
}
