import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dentaguru/core/constants/booking_rules_config.dart';
import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/admin/presentation/widgets/admin_global_visits_calendar.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_admin_overview.dart';
import 'package:dentaguru/features/dentist/presentation/widgets/doctor_visits_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookingRulesConfig.resetDefaults();
    BookingRulesConfig.debugNowOverride = DateTime(2026, 12, 10, 9, 0);
    ApiService.debugDoctorVisitsCalendarOverride = null;
    ApiService.debugAdminVisitsCalendarOverride = null;
  });

  tearDown(() {
    BookingRulesConfig.resetDefaults();
    ApiService.debugDoctorVisitsCalendarOverride = null;
    ApiService.debugAdminVisitsCalendarOverride = null;
  });

  group('Phase 1, 3, 4 & 6 — Doctor Visits Calendar Widget Tests', () {
    testWidgets(
      'Scenarios 1, 3, 4, 8, 9, 10 & 12: Doctor sees only own appointments, deduplicated actual visits, separate cancelled/no-show counts, referral tracking, and empty state on date with no visits',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final appointments = <PatientConsultationRequest>[
          // Patient 1 has two COMPLETED visits on 2026-12-10 with doc-1 -> 2 completed, 1 unique actual visit
          PatientConsultationRequest(
            id: 'apt-1',
            patientId: 'p-1',
            patientName: 'Ananya Rao',
            patientPhone: '9876543210',
            problemCategory: 'In-Person - Cardiology Checkup',
            problemDescription: 'Routine cardiac evaluation',
            symptoms: 'Mild fatigue',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 9),
            status: 'Completed',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            assignedDoctorSpecialty: 'Cardiology',
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '09:30 AM',
            consultationMode: 'In-Person',
          ),
          PatientConsultationRequest(
            id: 'apt-2',
            patientId: 'p-1',
            patientName: 'Ananya Rao',
            patientPhone: '9876543210',
            problemCategory: 'Online - Cardiology Follow-up',
            problemDescription: 'Report review',
            symptoms: 'None',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 9),
            status: 'Completed',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            assignedDoctorSpecialty: 'Cardiology',
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '11:00 AM',
            consultationMode: 'Online',
          ),
          // Patient 2 has a Pending/Confirmed appointment
          PatientConsultationRequest(
            id: 'apt-3',
            patientId: 'p-2',
            patientName: 'Rohan Verma',
            patientPhone: '9876543211',
            problemCategory: 'Online - Consultation',
            problemDescription: 'ECG consultation',
            symptoms: 'Palpitations',
            severity: 'Moderate',
            submittedAt: DateTime(2026, 12, 9),
            status: 'Confirmed',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            assignedDoctorSpecialty: 'Cardiology',
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '12:30 PM',
            consultationMode: 'Online',
          ),
          // Cancelled appointment
          PatientConsultationRequest(
            id: 'apt-4',
            patientId: 'p-3',
            patientName: 'Vikram Singh',
            patientPhone: '9876543212',
            problemCategory: 'In-Person - Checkup',
            problemDescription: 'Checkup',
            symptoms: 'None',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 9),
            status: 'Cancelled',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            assignedDoctorSpecialty: 'Cardiology',
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '02:00 PM',
            consultationMode: 'In-Person',
          ),
          // No-Show appointment
          PatientConsultationRequest(
            id: 'apt-5',
            patientId: 'p-4',
            patientName: 'Deepak Nair',
            patientPhone: '9876543213',
            problemCategory: 'In-Person - Checkup',
            problemDescription: 'Checkup',
            symptoms: 'None',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 9),
            status: 'NO_SHOW',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            assignedDoctorSpecialty: 'Cardiology',
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '03:00 PM',
            consultationMode: 'In-Person',
          ),
          // Another doctor's appointment (Scenario 10: must be excluded from doc-1 calendar!)
          PatientConsultationRequest(
            id: 'apt-other-doc',
            patientId: 'p-99',
            patientName: 'Unauthorized Patient',
            patientPhone: '9999999999',
            problemCategory: 'In-Person - Ortho',
            problemDescription: 'Knee pain',
            symptoms: 'Pain',
            severity: 'Moderate',
            submittedAt: DateTime(2026, 12, 9),
            status: 'Completed',
            assignedDoctorId: 'doc-2',
            assignedDoctorName: 'Dr. Meera Ortho',
            assignedDoctorSpecialty: 'Orthopedics',
            confirmedDate: '2026-12-10',
            confirmedTimeSlot: '10:00 AM',
            consultationMode: 'In-Person',
          ),
        ];

        final referrals = <PatientReferral>[
          // Unbooked referral on 2026-12-09T20:15:00Z (= 2026-12-10 in Asia/Kolkata IST!)
          PatientReferral(
            id: 'ref-unbooked',
            referrerPatientId: 'p-1',
            referrerPatientName: 'Ananya Rao',
            referrerPatientPhone: '9876543210',
            referredPatientId: 'p-unbooked',
            referredPatientName: 'Kiran Unbooked',
            referredPatientMobile: '9123456780',
            requiredSpecialist: 'Cardiology',
            clinicalComplaint: 'BP check',
            doctorId: 'doc-1',
            doctorName: 'Dr. Arjun Calendar',
            status: 'Pending',
            referralDate: DateTime.parse('2026-12-09T20:15:00.000Z'),
          ),
          // Referral for Ananya Rao (who completed consultation)
          PatientReferral(
            id: 'ref-completed',
            referrerPatientId: 'p-2',
            referrerPatientName: 'Rohan Verma',
            referrerPatientPhone: '9876543211',
            referredPatientId: 'p-1',
            referredPatientName: 'Ananya Rao',
            referredPatientMobile: '9876543210',
            requiredSpecialist: 'Cardiology',
            clinicalComplaint: 'Chest checkup',
            doctorId: 'doc-1',
            doctorName: 'Dr. Arjun Calendar',
            status: 'Accepted',
            referralDate: DateTime(2026, 12, 10, 10, 0),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DoctorVisitsCalendarSection(
                    doctorId: 'doc-1',
                    doctorName: 'Dr. Arjun Calendar',
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

        // Verify Doctor A sees 5 total appointments (excluding doc-2's appointment!)
        expect(find.byKey(const Key('doctor_visits_calendar_section')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_total_appointments')),
            matching: find.text('5'),
          ),
          findsOneWidget,
        );
        // Unique patients who actually visited = 1 (Ananya Rao had 2 completed appointments; Kiran Unbooked referral is NOT counted)
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_actual_visits')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        // Completed = 2, Accepted (Confirmed) = 1, Pending (awaiting action) = 0, Cancelled = 1, No-Show = 1
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_completed')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_accepted')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_pending')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_cancelled')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_no_show')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        // Referrals Received on 2026-12-10 (including 2026-12-09T20:15:00Z converted to IST) = 2
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_referrals_received')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );

        // Unauthorized patient from doc-2 must NOT appear
        expect(find.text('Unauthorized Patient'), findsNothing);

        // Referral tracking cards show booked/completed flags accurately
        expect(find.byKey(const Key('doctor_calendar_referral_card_ref-unbooked')), findsOneWidget);
        expect(find.text('Booked Appointment: No'), findsOneWidget);
        expect(find.text('Completed Visit: Yes'), findsOneWidget);

        // Scenario 2: Select a date with no appointments (2026-12-11)
        await tester.tap(find.byKey(const Key('doctor_calendar_day_2026-12-11')));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const Key('doctor_calendar_empty_visits_state')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_total_appointments')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('Phase 2, 3, 4 & 6 — Admin Global Visits Calendar Widget Tests', () {
    testWidgets(
      'Scenarios 5, 6, 7, 8 & 9: Admin sees all hospitals/clinics, accurate platform counts, hospital drill-down visit list, and hospital/doctor filters',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final clinics = <ClinicModel>[
          ClinicModel(
            id: 'c-apollo',
            clinicName: 'Apollo Heart Hospital',
            location: 'Hyderabad',
            phone: '9100000101',
            email: 'apollo@gshealth.test',
            verified: true,
            services: const ['Cardiology'],
          ),
          ClinicModel(
            id: 'c-kims',
            clinicName: 'KIMS Ortho Clinic',
            location: 'Warangal',
            phone: '9100000102',
            email: 'kims@gshealth.test',
            verified: true,
            services: const ['Orthopedics'],
          ),
        ];

        final doctors = <DoctorModel>[
          DoctorModel(
            id: 'doc-1',
            name: 'Dr. Arjun Calendar',
            specialty: 'Cardiology',
            qualification: 'MD, DM',
            experienceYears: 12,
            rating: 4.9,
            reviewCount: 40,
            clinicName: 'Apollo Heart Hospital',
            phone: '9211000001',
            email: 'arjun@gshealth.test',
            status: 'Available',
            nextAvailableSlots: const ['10:00 AM'],
            consultationFee: '₹800',
          ),
          DoctorModel(
            id: 'doc-2',
            name: 'Dr. Meera Ortho',
            specialty: 'Orthopedics',
            qualification: 'MS Ortho',
            experienceYears: 9,
            rating: 4.8,
            reviewCount: 25,
            clinicName: 'KIMS Ortho Clinic',
            phone: '9211000002',
            email: 'meera@gshealth.test',
            status: 'Available',
            nextAvailableSlots: const ['11:00 AM'],
            consultationFee: '₹700',
          ),
        ];

        final appointments = <AdminAppointmentItem>[
          const AdminAppointmentItem(
            id: 'adm-apt-1',
            patientName: 'Ananya Rao',
            phone: '9876543210',
            status: 'COMPLETED',
            dateRaw: '2026-12-10',
            timeSlot: '09:30 AM',
            dentistId: 'doc-1',
            dentistName: 'Dr. Arjun Calendar',
            doctorSpecialty: 'Cardiology',
            clinicId: 'c-apollo',
            clinicName: 'Apollo Heart Hospital',
            mode: 'IN-CLINIC',
            notes: '',
            treatment: 'In-Person - Cardiac Checkup',
          ),
          const AdminAppointmentItem(
            id: 'adm-apt-2',
            patientName: 'Rohan Verma',
            phone: '9876543211',
            status: 'CONFIRMED',
            dateRaw: '2026-12-10',
            timeSlot: '11:00 AM',
            dentistId: 'doc-1',
            dentistName: 'Dr. Arjun Calendar',
            doctorSpecialty: 'Cardiology',
            clinicId: 'c-apollo',
            clinicName: 'Apollo Heart Hospital',
            mode: 'ONLINE',
            notes: '',
            treatment: 'Online - Follow-up',
          ),
          const AdminAppointmentItem(
            id: 'adm-apt-3',
            patientName: 'Suresh Reddy',
            phone: '9876543215',
            status: 'COMPLETED',
            dateRaw: '2026-12-10',
            timeSlot: '10:00 AM',
            dentistId: 'doc-2',
            dentistName: 'Dr. Meera Ortho',
            doctorSpecialty: 'Orthopedics',
            clinicId: 'c-kims',
            clinicName: 'KIMS Ortho Clinic',
            mode: 'IN-CLINIC',
            notes: '',
            treatment: 'In-Person - Knee Evaluation',
          ),
        ];

        final referrals = <PatientReferral>[
          PatientReferral(
            id: 'adm-ref-1',
            referrerPatientId: 'p-1',
            referrerPatientName: 'Ananya Rao',
            referredPatientName: 'Unbooked Friend',
            referredPatientMobile: '9000011111',
            requiredSpecialist: 'Cardiology',
            clinicalComplaint: 'Checkup',
            doctorId: 'doc-1',
            doctorName: 'Dr. Arjun Calendar',
            status: 'Pending',
            referralDate: DateTime(2026, 12, 10, 11, 0),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AdminGlobalVisitsCalendarSection(
                    appointments: appointments,
                    clinics: clinics,
                    doctors: doctors,
                    patients: const [],
                    referrals: referrals,
                    initialSelectedDate: DateTime(2026, 12, 10),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Verify platform-wide counts on 2026-12-10:
        // Total scheduled = 3, Actual visits = 2 (Ananya & Suresh; unbooked referral NOT counted), Completed = 2, Pending = 1
        expect(find.byKey(const Key('admin_global_visits_calendar_section')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('admin_cal_stat_total_scheduled')),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('admin_cal_stat_actual_visits')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('admin_cal_stat_completed')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('admin_cal_stat_pending')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('admin_cal_stat_referrals')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        // Scenario 5: Both hospitals appear in the breakdown
        expect(find.byKey(const Key('admin_calendar_hospital_card_c-apollo')), findsOneWidget);
        expect(find.byKey(const Key('admin_calendar_hospital_card_c-kims')), findsOneWidget);

        // Click Apollo Heart Hospital card to drill down into its detailed patient visit list
        await tester.tap(find.byKey(const Key('admin_calendar_hospital_card_c-apollo')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const Key('admin_calendar_hospital_visits_header_c-apollo')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Scenario 13: Duplicate patient names with different patientIds/phones are NOT merged, while multiple appointments for the same patient ARE deduplicated',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // 3 completed appointments on 2026-12-12:
        // - 2 for Ravi Kumar #1 (patientId: 'pat-ravi-1', phone empty to verify patientId priority)
        // - 1 for Ravi Kumar #2 (patientId: 'pat-ravi-2', phone empty, identical name!)
        final doctorRequests = <PatientConsultationRequest>[
          PatientConsultationRequest(
            id: 'dup-doc-1',
            patientId: 'pat-ravi-1',
            patientName: 'Ravi Kumar',
            patientPhone: '',
            problemCategory: 'Cardiology',
            problemDescription: 'Morning visit',
            symptoms: 'None',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 12, 9, 0),
            status: 'Completed',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            confirmedDate: '2026-12-12',
            confirmedTimeSlot: '09:00 AM',
            consultationMode: 'In-Person',
          ),
          PatientConsultationRequest(
            id: 'dup-doc-2',
            patientId: 'pat-ravi-1',
            patientName: 'Ravi Kumar',
            patientPhone: '',
            problemCategory: 'Cardiology',
            problemDescription: 'Evening follow-up',
            symptoms: 'None',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 12, 17, 0),
            status: 'Completed',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            confirmedDate: '2026-12-12',
            confirmedTimeSlot: '05:00 PM',
            consultationMode: 'Online',
          ),
          PatientConsultationRequest(
            id: 'dup-doc-3',
            patientId: 'pat-ravi-2',
            patientName: 'Ravi Kumar',
            patientPhone: '',
            problemCategory: 'Cardiology',
            problemDescription: 'Different patient with same name',
            symptoms: 'None',
            severity: 'Low',
            submittedAt: DateTime(2026, 12, 12, 11, 0),
            status: 'Completed',
            assignedDoctorId: 'doc-1',
            assignedDoctorName: 'Dr. Arjun Calendar',
            confirmedDate: '2026-12-12',
            confirmedTimeSlot: '11:00 AM',
            consultationMode: 'In-Person',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DoctorVisitsCalendarSection(
                    doctorId: 'doc-1',
                    doctorName: 'Dr. Arjun Calendar',
                    doctorSpecialty: 'Cardiology',
                    assignedAppointments: doctorRequests,
                    receivedReferrals: const [],
                    initialSelectedDate: DateTime(2026, 12, 12),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Total appointments = 3, Completed = 3, Unique Actual Patient Visits = 2 (NOT 1!)
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_total_appointments')),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_completed')),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('doctor_cal_stat_actual_visits')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
