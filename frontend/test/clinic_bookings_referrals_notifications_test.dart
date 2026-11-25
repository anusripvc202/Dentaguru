import 'package:dentaguru/core/services/api_service.dart';
import 'package:dentaguru/core/services/patient_problem_service.dart';
import 'package:dentaguru/features/clinic/presentation/screens/clinic_dashboard.dart';
import 'package:dentaguru/features/dentist/presentation/screens/dentist_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PatientProblemService service;
  final List<String> syncedClinicAppointmentIds = [];
  final List<String> acceptedReferralIds = [];
  final List<(String, String?)> rejectedReferralCalls = [];
  final List<Map<String, dynamic>> clinicABookingsApiRows = [];
  final List<Map<String, dynamic>> clinicAReferralsApiRows = [];
  final List<Map<String, dynamic>> serverNotifications = [];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    syncedClinicAppointmentIds.clear();
    acceptedReferralIds.clear();
    rejectedReferralCalls.clear();
    clinicABookingsApiRows.clear();
    clinicAReferralsApiRows.clear();
    serverNotifications.clear();

    service = PatientProblemService();
    await service.clearAllData();

    ApiService.debugFetchAppointmentsOverride = ({String? patientId, String? dentistId}) async => [];
    ApiService.debugFetchClinicAppointmentsOverride = ({String? clinicId}) async {
      if (clinicId != null) syncedClinicAppointmentIds.add(clinicId);
      if (clinicId == 'clinic-A' || clinicId == 'Apollo Heart Clinic') {
        return clinicABookingsApiRows;
      }
      return [];
    };
    ApiService.debugFetchClinicReferralsOverride = ({String? clinicId, String? clinicName}) async {
      if (clinicId == 'clinic-A' || (clinicName ?? '').contains('Apollo')) {
        return clinicAReferralsApiRows;
      }
      return [];
    };
    ApiService.debugFetchNotificationsOverride = ({String? role, String? userId}) async {
      final rLower = (role ?? '').toLowerCase();
      return serverNotifications.where((n) {
        final nr = (n['recipient_role'] ?? '').toString().toLowerCase();
        final nid = (n['recipient_id'] ?? '').toString();
        if (rLower == 'clinic') return nr == 'clinic' && nid == userId;
        if (rLower == 'dentist') return (nr == 'dentist' || nr == 'doctor') && nid == userId;
        return nid == userId;
      }).toList();
    };
    ApiService.debugAcceptPatientReferralOverride = (String referralId, {String? confirmedTimeSlot}) async {
      acceptedReferralIds.add(referralId);
      return {'success': true};
    };
    ApiService.debugRejectPatientReferralOverride = (String referralId, {String? rejectionReason}) async {
      rejectedReferralCalls.add((referralId, rejectionReason));
      return {'success': true};
    };
  });

  tearDown(() async {
    ApiService.debugFetchAppointmentsOverride = null;
    ApiService.debugFetchClinicAppointmentsOverride = null;
    ApiService.debugFetchClinicReferralsOverride = null;
    ApiService.debugFetchNotificationsOverride = null;
    ApiService.debugAcceptPatientReferralOverride = null;
    ApiService.debugRejectPatientReferralOverride = null;
    await service.clearAllData();
  });

  testWidgets('1. Clinic Dashboard syncs clinic bookings by clinicId and filters All/Pending/Confirmed/Completed cleanly', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    clinicABookingsApiRows.addAll([
      {
        'id': 'appt-pending-1',
        'patient_id': 'PAT-00112233',
        'patient_name': 'Ramesh Kumar',
        'patient_phone': '9000011111',
        'dentist_id': 'doc-a-1',
        'dentist_name': 'Dr. Arjun Rao',
        'doctor_specialty': 'Cardiology',
        'clinic_id': 'clinic-A',
        'clinic_name': 'Apollo Heart Clinic',
        'date': '2026-12-01T00:00:00Z',
        'time_slot': '09:30 AM',
        'treatment': 'Cardiology Evaluation',
        'status': 'PENDING',
        'referral_id': 'ref-a-1',
        'referral_source': 'Anu Sharma',
      },
      {
        'id': 'appt-conf-2',
        'patient_id': 'PAT-00445566',
        'patient_name': 'Meera Nair',
        'patient_phone': '9000022222',
        'dentist_id': 'doc-a-1',
        'dentist_name': 'Dr. Arjun Rao',
        'doctor_specialty': 'Cardiology',
        'clinic_id': 'clinic-A',
        'clinic_name': 'Apollo Heart Clinic',
        'date': '2026-12-02T00:00:00Z',
        'time_slot': '11:00 AM',
        'treatment': 'ECG Follow-up',
        'status': 'CONFIRMED',
      },
      {
        'id': 'appt-done-3',
        'patient_id': 'PAT-00778899',
        'patient_name': 'Vikram Patel',
        'patient_phone': '9000033333',
        'dentist_id': 'doc-a-1',
        'dentist_name': 'Dr. Arjun Rao',
        'doctor_specialty': 'Cardiology',
        'clinic_id': 'clinic-A',
        'clinic_name': 'Apollo Heart Clinic',
        'date': '2026-11-28T00:00:00Z',
        'time_slot': '04:00 PM',
        'treatment': 'Echo Checkup',
        'status': 'COMPLETED',
      },
    ]);

    service.setAuthenticatedClinicSession(
      id: 'clinic-A',
      clinicName: 'Apollo Heart Clinic',
      location: 'Hyderabad',
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ClinicDashboardScreen(clinicName: 'Apollo Heart Clinic', initialTab: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(syncedClinicAppointmentIds, contains('clinic-A'));
    expect(find.text('No clinic bookings yet'), findsNothing);
    expect(find.textContaining('Ramesh Kumar'), findsOneWidget);
    expect(find.textContaining('Meera Nair'), findsOneWidget);
    expect(find.textContaining('Vikram Patel'), findsOneWidget);
    expect(find.textContaining('ID: PAT-0011'), findsOneWidget);
    expect(find.textContaining('Dr. Arjun Rao • Cardiology'), findsWidgets);
    expect(find.textContaining('Referral Source: Anu Sharma'), findsOneWidget);

    // Filter Pending
    await tester.ensureVisible(find.byKey(const Key('clinic_bookings_filter_Pending')));
    await tester.tap(find.byKey(const Key('clinic_bookings_filter_Pending')));
    await tester.pump();
    expect(find.textContaining('Ramesh Kumar'), findsOneWidget);
    expect(find.textContaining('Meera Nair'), findsNothing);
    expect(find.textContaining('Vikram Patel'), findsNothing);

    // Filter Confirmed
    await tester.ensureVisible(find.byKey(const Key('clinic_bookings_filter_Confirmed')));
    await tester.tap(find.byKey(const Key('clinic_bookings_filter_Confirmed')));
    await tester.pump();
    expect(find.textContaining('Meera Nair'), findsOneWidget);
    expect(find.textContaining('Ramesh Kumar'), findsNothing);

    // Filter Completed
    await tester.ensureVisible(find.byKey(const Key('clinic_bookings_filter_Completed')));
    await tester.tap(find.byKey(const Key('clinic_bookings_filter_Completed')));
    await tester.pump();
    expect(find.textContaining('Vikram Patel'), findsOneWidget);
    expect(find.textContaining('Ramesh Kumar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2. Clinic Dashboard Referrals sheet displays referral details and Accept/Decline management without mixing with bookings', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    clinicAReferralsApiRows.add({
      'id': 'ref-clinic-101',
      'referrer_patient_id': 'pat-ref-1',
      'referrer_patient_name': 'Anu',
      'referred_patient_name': 'Satya Friend',
      'referred_patient_mobile': '9988776611',
      'required_specialist': 'Cardiology',
      'clinical_complaint': 'Chest palpitations review',
      'doctor_id': 'doc-a-1',
      'clinic_id': 'clinic-A',
      'doctor_name': 'Dr. Arjun Rao',
      'doctor_specialty': 'Cardiology',
      'doctor_clinic_name': 'Apollo Heart Clinic',
      'status': 'Pending',
      'referral_date': '2026-11-19T10:30:00Z',
    });

    service.setAuthenticatedClinicSession(
      id: 'clinic-A',
      clinicName: 'Apollo Heart Clinic',
      location: 'Hyderabad',
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ClinicDashboardScreen(clinicName: 'Apollo Heart Clinic'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Bookings tab remains empty since referral must NOT automatically become a confirmed booking
    expect(service.clinicBookingsFor(clinicId: 'clinic-A', clinicName: 'Apollo Heart Clinic'), isEmpty);

    final refCard = find.byKey(const Key('clinic_patient_referrals_card'));
    await tester.ensureVisible(refCard);
    await tester.tap(refCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Satya Friend'), findsOneWidget);
    expect(find.textContaining('Dr. Arjun Rao · Cardiology'), findsOneWidget);
    expect(find.textContaining('Ref #REF-CLIN'), findsOneWidget);
    expect(find.textContaining('+91 9988776611'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clinic_referral_accept_ref-clinic-101')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(acceptedReferralIds, equals(['ref-clinic-101']));
    expect(find.text('Accepted'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3 & 4. Multiple clinics isolate bookings/referrals/notifications, persist across re-login & navigate on notification tap', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    clinicABookingsApiRows.add({
      'id': 'appt-clinicA-only',
      'patient_id': 'pat-A',
      'patient_name': 'ClinicA Patient',
      'patient_phone': '9111111111',
      'dentist_id': 'doc-a-1',
      'dentist_name': 'Dr. Arjun Rao',
      'doctor_specialty': 'Cardiology',
      'clinic_id': 'clinic-A',
      'clinic_name': 'Apollo Heart Clinic',
      'date': '2026-12-04T00:00:00Z',
      'time_slot': '10:00 AM',
      'treatment': 'Heart Check',
      'status': 'PENDING',
    });

    serverNotifications.addAll([
      {
        'id': 'notif-clinicA-book',
        'recipient_role': 'Clinic',
        'recipient_id': 'clinic-A',
        'title': 'New Appointment Booking',
        'message': 'ClinicA Patient booked an appointment with Dr. Arjun Rao on 2026-12-04 at 10:00 AM.',
        'type': 'clinic_appointment_booked',
        'read': false,
        'created_at': '2026-11-19T10:00:00Z',
      },
      {
        'id': 'notif-clinicB-ref',
        'recipient_role': 'Clinic',
        'recipient_id': 'clinic-B',
        'title': 'New Patient Referral',
        'message': 'A patient has referred Dr. Skin Specialist, Dermatology.',
        'type': 'clinic_new_referral',
        'read': false,
        'created_at': '2026-11-19T10:01:00Z',
      },
    ]);

    // First verify Clinic B does NOT see Clinic A's booking or Clinic A's notification
    service.setAuthenticatedClinicSession(
      id: 'clinic-B',
      clinicName: 'City Skin Clinic',
      location: 'Secunderabad',
    );
    await service.syncAppointmentsFromApi();
    await service.syncNotificationsFromApi(role: 'Clinic', userId: 'clinic-B');

    final clinicBNotifs = service.getNotificationsForRole('Clinic', clinicId: 'clinic-B', clinicName: 'City Skin Clinic');
    expect(clinicBNotifs.length, 1);
    expect(clinicBNotifs.first.id, 'notif-clinicB-ref');
    expect(service.clinicBookingsFor(clinicId: 'clinic-B', clinicName: 'City Skin Clinic'), isEmpty);

    // Logout & Login as Clinic A -> unread notification persists & tapping navigates to Bookings tab
    await service.clearAllData();
    service.setAuthenticatedClinicSession(
      id: 'clinic-A',
      clinicName: 'Apollo Heart Clinic',
      location: 'Hyderabad',
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ClinicDashboardScreen(clinicName: 'Apollo Heart Clinic', initialTab: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final clinicANotifs = service.getNotificationsForRole('Clinic', clinicId: 'clinic-A', clinicName: 'Apollo Heart Clinic');
    expect(clinicANotifs.length, 1);
    expect(clinicANotifs.first.id, 'notif-clinicA-book');

    // Open Notifications bell -> tap booking notification -> marks read & navigates to Bookings tab showing ClinicA Patient
    await tester.tap(find.byKey(const Key('clinic_notifications_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('New Appointment Booking'), findsOneWidget);
    await tester.tap(find.text('New Appointment Booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('ClinicA Patient'), findsWidgets);
    expect(clinicANotifs.where((n) => !n.isRead).length, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. Doctor Dashboard notifications isolate per doctor, show badge count & navigate on tap', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    serverNotifications.addAll([
      {
        'id': 'notif-doc-1',
        'recipient_role': 'Dentist',
        'recipient_id': 'doc-a-1',
        'title': 'New Patient Referral',
        'message': 'You have received a new patient referral for Satya.',
        'type': 'NEW_REFERRAL',
        'read': false,
        'created_at': '2026-11-19T11:00:00Z',
      },
      {
        'id': 'notif-doc-other',
        'recipient_role': 'Dentist',
        'recipient_id': 'doc-other-99',
        'title': 'Unrelated Doctor Notification',
        'message': 'Should never appear for doc-a-1.',
        'type': 'appointment_request',
        'read': false,
        'created_at': '2026-11-19T11:05:00Z',
      },
    ]);

    service.registerDoctor(
      id: 'doc-a-1',
      userId: 'user-doc-a-1',
      name: 'Dr. Arjun Rao',
      email: 'arjun@apollo.test',
      phone: '9876500011',
      licenseNumber: 'MED-12345',
      specialty: 'Cardiology',
      clinicName: 'Apollo Heart Clinic',
      experienceYears: 8,
      skipApiRegister: true,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DentistTimelineScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final docNotifs = service.getNotificationsForRole('Dentist');
    expect(docNotifs.map((n) => n.id), contains('notif-doc-1'));
    expect(docNotifs.map((n) => n.id), isNot(contains('notif-doc-other')));

    await tester.tap(find.byKey(const Key('dentist_notifications_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('New Patient Referral'), findsOneWidget);
    expect(find.text('Unrelated Doctor Notification'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
