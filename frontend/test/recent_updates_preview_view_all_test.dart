import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentaguru/core/models/referral_model.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/core/widgets/recent_updates_preview_section.dart';
import 'package:dentaguru/features/admin/presentation/widgets/gs_health_admin_overview.dart';
import 'package:dentaguru/features/clinic/presentation/widgets/gs_health_clinic_views.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GS Health — Recent Updates Preview (Max 2) & View All Across All Dashboards', () {
    test('1. takeLatestPreviewRecords sorts by latest date/time descending and caps at 2 records', () {
      final dates = [
        DateTime(2026, 11, 20, 9, 0),
        DateTime(2026, 11, 26, 14, 30),
        DateTime(2026, 11, 22, 11, 0),
        DateTime(2026, 11, 25, 18, 15),
      ];
      final preview = takeLatestPreviewRecords<DateTime>(
        dates,
        compareDesc: (a, b) => b.compareTo(a),
      );
      expect(preview.length, equals(2));
      expect(preview[0], equals(DateTime(2026, 11, 26, 14, 30)));
      expect(preview[1], equals(DateTime(2026, 11, 25, 18, 15)));
    });

    testWidgets(
      '2. Admin Dashboard Overview displays only the latest 2 records for Requests, Referrals, Appointments, Doctors & Clinics, supports View All navigation, and renders required fields',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1024, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool openedAllAppointments = false;
        bool openedAllRequests = false;
        bool openedAllReferrals = false;
        bool openedAllDoctors = false;
        bool openedAllClinics = false;

        final appointments = List.generate(
          4,
          (i) => AdminAppointmentItem(
            id: 'appt-$i',
            patientName: 'Patient $i',
            phone: '980000000$i',
            status: 'CONFIRMED',
            dateRaw: '2026-11-2${i + 1}T10:00:00.000Z',
            timeSlot: '10:00 AM',
            dentistName: 'Dr. Specialist $i',
            clinicName: 'Clinic $i',
            mode: 'IN-CLINIC',
            notes: '',
            treatment: 'Consultation',
          ),
        );

        final requests = List.generate(
          4,
          (i) => PatientConsultationRequest(
            id: 'REQ-10$i',
            patientName: 'Request Patient $i',
            patientPhone: '985550000$i',
            problemCategory: 'Dental Pain $i',
            problemDescription: 'Molar discomfort $i',
            severity: 'Moderate',
            submittedAt: DateTime(2026, 11, 20 + i, 11, 30),
            status: 'Pending Admin Review',
          ),
        );

        final referrals = List.generate(
          4,
          (i) => PatientReferral(
            id: 'REF-20$i',
            referrerPatientId: 'pat-$i',
            referrerPatientName: 'Dr. Referrer $i',
            referredPatientName: 'Referred Patient $i',
            referredPatientMobile: '981110000$i',
            referredPatientAge: '30',
            referredPatientGender: 'Female',
            clinicalComplaint: 'Toothache',
            requiredSpecialist: 'Endodontics',
            doctorId: 'doc-$i',
            doctorName: 'Dr. Target $i',
            referralDate: DateTime(2026, 11, 20 + i, 14, 15),
            createdAt: DateTime(2026, 11, 20 + i, 14, 15),
            status: 'Pending',
          ),
        );

        final doctors = List.generate(
          4,
          (i) => DoctorModel(
            id: 'doc-$i',
            name: 'Dr. Registered $i',
            specialty: 'Cardiology',
            qualification: 'MD',
            experienceYears: 6,
            rating: 4.9,
            reviewCount: 10,
            clinicName: 'Lotus Clinic',
            phone: '982220000$i',
            email: 'doc$i@gshealth.in',
            status: 'Available',
            nextAvailableSlots: const [],
            consultationFee: '500',
          ),
        );

        final clinics = List.generate(
          4,
          (i) => ClinicModel(
            id: 'cli-$i',
            clinicName: 'Registered Clinic $i',
            location: 'Address $i',
            clinicAddress: 'Address $i',
            city: 'Mumbai',
            state: 'Maharashtra',
            pincode: '40000$i',
            associatedDoctorsCount: i + 1,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: GsHealthAdminOverview(
                  stats: const [],
                  waitingCount: 0,
                  clinicsAction: const AdminQuickActionData(
                    id: 'clinics',
                    label: 'Clinics',
                    icon: Icons.local_hospital_outlined,
                  ),
                  referralsAction: const AdminQuickActionData(
                    id: 'referrals',
                    label: 'Referrals',
                    icon: Icons.share_outlined,
                  ),
                  sponsoredAction: const AdminQuickActionData(
                    id: 'ads',
                    label: 'Ads',
                    icon: Icons.campaign_outlined,
                  ),
                  smsAction: const AdminQuickActionData(
                    id: 'sms',
                    label: 'SMS',
                    icon: Icons.sms_outlined,
                  ),
                  ads: const [],
                  appointments: appointments,
                  onViewAllAppointments: () => openedAllAppointments = true,
                  recentRequests: requests,
                  onViewAllRequests: () => openedAllRequests = true,
                  recentReferrals: referrals,
                  onViewAllReferrals: () => openedAllReferrals = true,
                  recentDoctors: doctors,
                  onViewAllDoctors: () => openedAllDoctors = true,
                  recentClinics: clinics,
                  onViewAllClinics: () => openedAllClinics = true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No Calendar View option on Overview
        expect(find.text('Calendar View'), findsNothing);

        // Only 2 appointments shown initially (sorted descending: Patient 3 and Patient 2)
        expect(find.byKey(const Key('admin_appointment_card_0')), findsOneWidget);
        expect(find.byKey(const Key('admin_appointment_card_1')), findsOneWidget);
        expect(find.byKey(const Key('admin_appointment_card_2')), findsNothing);
        expect(find.text('Patient 3'), findsOneWidget);
        expect(find.text('Patient 2'), findsOneWidget);
        expect(find.text('Patient 0'), findsNothing);

        // Only 2 requests shown initially (sorted descending: Request Patient 3 & 2)
        // Displays Request ID, Patient Name, Request Type, Request Date and Status
        expect(find.byKey(const Key('admin_recent_request_card_0')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_request_card_1')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_request_card_2')), findsNothing);
        expect(find.textContaining('Request Patient 3'), findsOneWidget);
        expect(find.textContaining('Request Patient 2'), findsOneWidget);
        expect(find.textContaining('Request Patient 0'), findsNothing);
        expect(find.textContaining('Request ID: REQ-103'), findsOneWidget);
        expect(find.textContaining('Request ID: REQ-102'), findsOneWidget);
        expect(find.textContaining('Dental Pain 3'), findsWidgets);
        expect(find.textContaining('Dental Pain 2'), findsWidgets);

        // Only 2 referrals shown initially (sorted descending: Referred Patient 3 & 2)
        // Displays Referral ID, Patient Name, Referring Doctor, Referred Doctor, Referral Date and Status
        expect(find.byKey(const Key('admin_recent_referral_card_0')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_referral_card_1')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_referral_card_2')), findsNothing);
        expect(find.textContaining('Referred Patient 3'), findsOneWidget);
        expect(find.textContaining('Referred Patient 2'), findsOneWidget);
        expect(find.textContaining('Referred Patient 0'), findsNothing);
        expect(find.textContaining('Referral ID: REF-203'), findsOneWidget);
        expect(find.textContaining('Referral ID: REF-202'), findsOneWidget);
        expect(find.textContaining('Referring: Dr. Referrer 3'), findsOneWidget);
        expect(find.textContaining('Referred: Dr. Target 3'), findsOneWidget);

        // Only 2 doctors shown initially
        expect(find.byKey(const Key('admin_recent_doctor_card_0')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_doctor_card_1')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_doctor_card_2')), findsNothing);

        // Only 2 clinics shown initially
        expect(find.byKey(const Key('admin_recent_clinic_card_0')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_clinic_card_1')), findsOneWidget);
        expect(find.byKey(const Key('admin_recent_clinic_card_2')), findsNothing);

        // Tap View All buttons and verify navigation callbacks fire
        await tester.ensureVisible(find.byKey(const Key('admin_view_all_appointments_btn')));
        await tester.tap(find.byKey(const Key('admin_view_all_appointments_btn')));
        await tester.ensureVisible(find.byKey(const Key('admin_view_all_requests_btn')));
        await tester.tap(find.byKey(const Key('admin_view_all_requests_btn')));
        await tester.ensureVisible(find.byKey(const Key('admin_view_all_referrals_btn')));
        await tester.tap(find.byKey(const Key('admin_view_all_referrals_btn')));
        await tester.ensureVisible(find.byKey(const Key('admin_view_all_doctors_btn')));
        await tester.tap(find.byKey(const Key('admin_view_all_doctors_btn')));
        await tester.ensureVisible(find.byKey(const Key('admin_view_all_clinics_btn')));
        await tester.tap(find.byKey(const Key('admin_view_all_clinics_btn')));

        expect(openedAllAppointments, isTrue);
        expect(openedAllRequests, isTrue);
        expect(openedAllReferrals, isTrue);
        expect(openedAllDoctors, isTrue);
        expect(openedAllClinics, isTrue);
      },
    );

    testWidgets(
      '3. Clinic Dashboard Overview displays only the latest 2 Appointments, Recently Added Doctors & Recent Patient Activity and navigates via View All',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1024, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool viewedAllAppts = false;
        bool viewedAllDocs = false;
        bool viewedAllActivity = false;

        final doctors = List.generate(
          4,
          (i) => DoctorModel(
            id: 'cli-doc-$i',
            name: 'Dr. Clinic Doc $i',
            specialty: 'Dentistry',
            qualification: 'BDS',
            experienceYears: 5,
            rating: 4.8,
            reviewCount: 12,
            clinicName: 'Lotus Care Clinic',
            phone: '983330000$i',
            email: 'cdoc$i@gshealth.in',
            status: 'Available',
            nextAvailableSlots: const [],
            consultationFee: '500',
          ),
        );

        final bookings = List.generate(
          4,
          (i) => PatientConsultationRequest(
            id: 'bk-$i',
            patientName: 'Clinic Patient $i',
            patientPhone: '984440000$i',
            problemCategory: 'Dental Checkup $i',
            problemDescription: 'Routine checkup',
            severity: 'Mild',
            submittedAt: DateTime(2026, 11, 20 + i, 10, 0),
            status: 'Confirmed',
            assignedDoctorName: 'Dr. Clinic Doc $i',
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: GsHealthClinicOverview(
                  clinicName: 'Lotus Care Clinic',
                  clinicLocation: '45 Linking Road, Mumbai',
                  coverImageUrl: '',
                  isFeatured: false,
                  featuredPlan: '',
                  unreadNotifications: 0,
                  referralsCount: 0,
                  visitsTodayCount: 4,
                  awaitingConfirmationCount: 1,
                  completedVisitsCount: 2,
                  attachedDoctors: doctors,
                  recentAppointments: bookings,
                  onNotifications: () {},
                  onProfile: () {},
                  onEditDetails: () {},
                  onOpenFeaturedPlan: () {},
                  onOpenReferrals: () {},
                  onOpenAdvertise: () {},
                  onTapBookingsStat: (_) {},
                  onViewAllAppointments: () => viewedAllAppts = true,
                  onViewAllDoctors: () => viewedAllDocs = true,
                  onViewAllPatientActivity: () => viewedAllActivity = true,
                  onAddDoctor: () {},
                  onRefresh: () async {},
                  onToggleDoctorStatus: (_) {},
                  onViewDoctorProfile: (_) {},
                  onEditDoctor: (_) {},
                  onManageDoctorSlots: (_) {},
                  onRemoveDoctor: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Latest Appointments: only 2 cards rendered (latest Clinic Patient 3 & Clinic Patient 2)
        expect(find.byKey(const Key('clinic_latest_appointment_card_0')), findsOneWidget);
        expect(find.byKey(const Key('clinic_latest_appointment_card_1')), findsOneWidget);
        expect(find.byKey(const Key('clinic_latest_appointment_card_2')), findsNothing);

        // Recently Added Doctors: only latest 2 doctors rendered (Dr. Clinic Doc 3 & Dr. Clinic Doc 2)
        expect(find.text('Dr. Clinic Doc 3'), findsWidgets);
        expect(find.text('Dr. Clinic Doc 2'), findsWidgets);
        expect(find.text('Dr. Clinic Doc 0'), findsNothing);

        // Recent Patient Activity: only 2 cards rendered
        expect(find.byKey(const Key('clinic_recent_patient_activity_card_0')), findsOneWidget);
        expect(find.byKey(const Key('clinic_recent_patient_activity_card_1')), findsOneWidget);
        expect(find.byKey(const Key('clinic_recent_patient_activity_card_2')), findsNothing);

        await tester.ensureVisible(find.byKey(const Key('clinic_view_all_appointments_btn')));
        await tester.tap(find.byKey(const Key('clinic_view_all_appointments_btn')));
        await tester.ensureVisible(find.byKey(const Key('clinic_view_all_doctors_btn')));
        await tester.tap(find.byKey(const Key('clinic_view_all_doctors_btn')));
        await tester.ensureVisible(find.byKey(const Key('clinic_view_all_patient_activity_btn')));
        await tester.tap(find.byKey(const Key('clinic_view_all_patient_activity_btn')));

        expect(viewedAllAppts, isTrue);
        expect(viewedAllDocs, isTrue);
        expect(viewedAllActivity, isTrue);
      },
    );

    testWidgets(
      '4. RecentUpdatesPreviewSection enforces 2-record preview limit, fires View All, and shows empty state when empty',
      (WidgetTester tester) async {
        bool viewAllTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  RecentUpdatesPreviewSection(
                    sectionKey: const Key('test_preview_populated'),
                    viewAllKey: const Key('test_preview_view_all'),
                    title: 'Recent Consultations',
                    totalCount: 5,
                    onViewAll: () => viewAllTapped = true,
                    emptyTitle: 'No consultations yet.',
                    previewChildren: List.generate(
                      5,
                      (i) => RecentUpdatePreviewCard(
                        cardKey: Key('test_preview_item_$i'),
                        title: 'Consultation $i',
                        subtitle: 'Dr. Test $i',
                      ),
                    ),
                  ),
                  const RecentUpdatesPreviewSection(
                    sectionKey: Key('test_preview_empty'),
                    emptyStateKey: Key('test_preview_empty_card'),
                    title: 'Upcoming Appointments',
                    totalCount: 0,
                    emptyTitle: 'No upcoming appointments yet.',
                    previewChildren: [],
                  ),
                ],
              ),
            ),
          ),
        );

        // Only 2 of 5 preview children are rendered
        expect(find.byKey(const Key('test_preview_item_0')), findsOneWidget);
        expect(find.byKey(const Key('test_preview_item_1')), findsOneWidget);
        expect(find.byKey(const Key('test_preview_item_2')), findsNothing);

        // Empty state card is rendered for empty section
        expect(find.byKey(const Key('test_preview_empty_card')), findsOneWidget);
        expect(find.text('No upcoming appointments yet.'), findsOneWidget);

        await tester.tap(find.byKey(const Key('test_preview_view_all')));
        expect(viewAllTapped, isTrue);
      },
    );
  });
}
